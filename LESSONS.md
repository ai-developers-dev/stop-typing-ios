# Lessons: iOS Audio Session + Keyboard Extension Dictation

Hard-won knowledge from shipping Stop Typing's dictation keyboard. Read this before touching `BackgroundDictationService` or the keyboard's Darwin/liveness logic. It will save you days.

## The three iOS rules we can't break

### 1. `UIBackgroundModes=audio` does NOT guarantee indefinite background execution

From Apple's docs on `AVAudioSession.InterruptionReason.appWasSuspended`:

> *"Starting in iOS 10, the system deactivates the audio session of most apps when it suspends the app process."*

The `audio` background mode prevents *immediate* deactivation when we go to background, but iOS still suspends the process after idle. Once suspended, the audio session dies. An idle `AVAudioEngine` with a dummy tap extends the window but does not make it infinite.

**Implication:** Any architecture that assumes "we're always alive in background" is wrong. The session will die. Plan for recovery, don't plan for prevention.

### 2. `setActive(true)` from background fails with `cannotInterruptOthers` / `insufficientPriority`

Error codes we hit constantly:

- **560557684** = `AVAudioSession.ErrorCode.cannotInterruptOthers` — *"an attempt to make a nonmixable audio session active while the app was in the background"*
- **561017449** = `AVAudioSession.ErrorCode.insufficientPriority` — *"the app isn't allowed to set the audio category because it's in use by another app"*
- **561015905** = `cannotStartPlaying` — similar family

These are **not recoverable in-process**. No retry count saves you. The only fix is getting the main app foregrounded. Research ruled out every other workaround (see "Dead ends" below).

### 3. Keyboard extensions cannot directly wake or foreground the host app

From `NSExtensionContext.open(_:completionHandler:)` docs:

> *"In iOS, the Today and iMessage app extension points support this method."*

Keyboard extensions are explicitly **not** in that list. In practice `extensionContext.open(url)` compiles and sometimes works for keyboards on recent iOS, but it's unsanctioned and may return `false`. The sanctioned fallback is: the user's finger has to tap into the app itself.

**Wispr Flow admits this on their onboarding:** *"We wish you didn't have to switch apps to use Flow, but Apple now requires this to activate the microphone."* If Wispr Flow — with a well-funded senior iOS team — can't escape this rule, we can't either.

## The architecture we landed on

Based on the rules above, the only viable pattern is a variant of Wispr Flow's "Flow Session":

```
Keyboard                              Main App
────────                              ────────
Has session?  ◀── heartbeat ──────────  Writes heartbeat every 2s
                                        while alive
    │
    ├── yes → show mic button
    │         User taps → Darwin startDictation ──▶ startRecordingAsync
    │                                                 (works because session
    │                                                  is fresh)
    │
    └── no  → show "Start ST" button
              User taps → extensionContext.open("stoptyping://activate")
                                         │
                                         ▼
                                    App foregrounds
                                    handleForeground() → rebuildAudioPipelineFromScratch()
                                    (setActive works here because we're foreground)
                                         │
                                         ▼
                                    DictationOverlayView shows
                                    "Reconnecting microphone…" → "✅ Ready"
                                         │
              User swipes back ◀─────────┘
              keyboard sees fresh heartbeat → mic button returns
              User taps → recording works
```

### Critical liveness signal: heartbeat, not `sessionActive`

`sessionActive` is sticky — it only clears on explicit `deactivateSession()`. When iOS suspends the app, `sessionActive` stays `true` forever on disk. **This made the keyboard lie to the user**: mic button shown, user taps, dead session, confused user.

The fix: gate the keyboard's `isAppAlive` on `SharedDefaults.isAppAlive()`, which checks whether a heartbeat has been written within the last 10 seconds. When iOS suspends the app, the 2s heartbeat timer stops firing, and within 10s the keyboard flips to "Start ST". See `KeyboardViewController.refreshState()`.

## The full Apple-documented recovery path (for `mediaServicesWereReset`)

From `AVAudioSession.mediaServicesWereResetNotification`:

> *"Respond to these events by reinitializing your app's audio objects and resetting your audio session's category, options, and mode configuration."*

This is what `rebuildAudioPipelineFromScratch()` does:

1. Stop current engine, remove all taps
2. `audioEngine = nil` (release it)
3. Cancel lingering recognition state
4. `try session.setActive(false, options: .notifyOthersOnDeactivation)` — zombie teardown
5. ~80ms breather so the AV daemon notices the deactivation
6. `setCategory` → `setMode` → `setActive(true)` (works because we're in foreground)
7. `setPreferredInput(builtInMic)` — forces iOS to re-bind the hardware route (otherwise a stale Bluetooth route can deliver zeros even when setActive succeeded)
8. Create fresh `AVAudioEngine`
9. Install idle tap, `prepare()`, `start()`
10. Write fresh heartbeat + bootId

## Gotchas that cost us days

### Parallel rebuild race

`handleForeground` (fires on scenePhase `.active`) and `DictationOverlayView.onAppear` → `activateSession` both used to schedule `rebuildAudioPipelineFromScratch` when the pipeline was stale. Two rebuilds raced, one tore down the engine the other just built, leaving the pipeline half-broken. Symptom: user taps Start ST → comes back → mic button shown → tap mic → silent failure → "Start ST" returns.

Fix: `handleForeground` owns the rebuild; `activateSession`'s already-active branch just writes a fresh heartbeat and falls through to the debounced `reactivateAudioPipeline`. Plus `rebuildInProgress` re-entry guard as a safety net.

### "setActive succeeded but mic delivers zeros"

A successful `setActive(true)` does **not** guarantee the hardware route is live. After wake-from-idle or a disconnected Bluetooth device, iOS can leave the route pointing at a dead input and deliver RMS ~0.0004 (i.e. pure zeros). Symptom: `recordingStarted` fires, first audio buffer arrives in ~200ms, but every `audioLevel` log shows `rms=0.0004` for the entire recording.

Fix: `forcePreferredBuiltInMic()` — call `session.setPreferredInput(builtInMicPort)` right after `setActive(true)`. Re-binds the hardware to a known-good device.

### Darwin notifications don't wake suspended apps

When the main app is suspended, Darwin notifications don't fire the handler — they're **queued** until iOS schedules the process to resume. We saw the keyboard fire `START dictation` at `9:47:36` / `9:47:40` / `9:47:43`, and the main app logged `Darwin: startDictation` at `9:47:59` — 16 seconds later. Plan for this: do not assume Darwin = instant delivery.

### `onRecordingFailed` should also clear `isAppAlive`

Without this, a failed recording leaves the keyboard on the mic toolbar in a state where every tap fails the same way. Clearing `isAppAlive` bounces the user back to "Start ST" so they can reopen the app and retry.

## Dead ends we explored and ruled out

- **Silent-mic in-flight recovery** (detect `rms < 0.001` for 15 buffers → tear down and re-setup mid-recording). Can't work: if the mic is dead from background, no amount of teardown inside the recording flow gets a live route. Removed.
- **Extended retry counts on `setActive(true)`**. Bugs not quantity — 9 retries fail exactly like 2 retries. The error is "another app holds audio priority", no retry fixes that.
- **`.mixWithOthers` as a rescue config**. Already our first-attempt config. Doesn't help when another app has *exclusive* audio (call, Siri).
- **Responder chain walk to reach `UIApplication`** (the old `UIResponder.next` loop to call `open()`). Broken on iOS 18+, unsanctioned, never worked reliably.
- **`NSXPCConnection.suspend` selector trick to auto-return from the app back to the previous app**. Shipped by some apps, App Store-risky, Wispr Flow explicitly chose not to use it — they show the "swipe right at the bottom" coach mark instead. We follow their lead.
- **`AVAudioEngine.reset()`** as a recovery mechanism. Apple docs don't recommend it for recovery — they specify full teardown and rebuild.

## Notifications we observe

All routed into `BackgroundDictationService`:

| Notification | Handler |
|---|---|
| `AVAudioSession.interruptionNotification` | `.began` → mark session stale. `.ended` → try `reactivateAudioPipeline` |
| `AVAudioSession.mediaServicesWereResetNotification` | Mark session stale + zero heartbeat (user-visible: keyboard shows "Start ST") |
| `AVAudioSession.mediaServicesWereLostNotification` | Same as above |
| `.AVAudioEngineConfigurationChange` | Mark stale + try `reactivateAudioPipeline` |

## Files that carry the knowledge

- `StopTyping/Services/BackgroundDictationService.swift` — `handleForeground`, `rebuildAudioPipelineFromScratch`, `setupAudioSessionWithRetry`, `forcePreferredBuiltInMic`, `logCurrentRoute`, `updateAudioLevel`
- `StopTyping/Features/Recording/DictationOverlayView.swift` — pipelineStatus banner showing "Reconnecting microphone…" → "Microphone ready"
- `StopTypingKeyboard/KeyboardViewController.swift` — heartbeat-based `isAppAlive` check, `onRecordingFailed` behavior, `openMainApp` + fallback hint
- `Shared/SharedDefaults.swift` — `isAppAlive()` (10s heartbeat window), `isCurrentBoot()` (reboot detection via `bootId`), `writeHeartbeat()`

## Apple docs references

- [Configuring background execution modes](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes)
- [`AVAudioSession.InterruptionReason.appWasSuspended`](https://developer.apple.com/documentation/avfaudio/avaudiosession/interruptionreason/appwassuspended)
- [`AVAudioSession.ErrorCode.cannotInterruptOthers`](https://developer.apple.com/documentation/coreaudiotypes/avaudiosession/errorcode/cannotinterruptothers)
- [`mediaServicesWereResetNotification`](https://developer.apple.com/documentation/avfaudio/avaudiosession/mediaserviceswereresetnotification)
- [`AVAudioEngineConfigurationChangeNotification`](https://developer.apple.com/documentation/avfaudio/avaudioengineconfigurationchangenotification)
- [`NSExtensionContext.open(_:completionHandler:)`](https://developer.apple.com/documentation/foundation/nsextensioncontext/open(_:completionhandler:))
- [`SFSpeechRecognizer`](https://developer.apple.com/documentation/speech/sfspeechrecognizer) (1-minute limit for server-based; on-device has no limit)
- WWDC19 Session 256: [Advances in Speech Recognition](https://developer.apple.com/videos/play/wwdc2019/256/)

## The one-line summary

**We cannot keep the audio session alive forever in background. Our job is to detect death promptly, ask the user to tap the app, rebuild the pipeline while foregrounded, and let them swipe back.** Everything else is plumbing for this one idea.
