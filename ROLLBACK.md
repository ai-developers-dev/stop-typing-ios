# Rollback Guide

## Known-Good Rollback Point: `stable-v1-keyboard-always-active`

This is the **last verified state** where the keyboard stays active across sleep/wake/close without ever prompting the user to "Start ST" again.

**Commit:** `03870c3` — "Self-heal audio after sleep; fresh overlay on deep link; onboarding to activation"

**Date tagged:** 2026-04-10

### What works at this rollback point

- User activates the session once
- Keyboard shows the active mic toolbar in any app (Messages, etc.)
- Phone can sleep for hours and wake — keyboard stays active
- User can close apps, switch apps, lock phone, walk away — no "Start ST" nag
- Sleep/wake self-healing via `AVAudioSession.interruptionNotification`
- Dictation overlay refreshes on every deep link (never stale)
- Onboarding flows directly into the activation overlay
- Dynamic Island Live Activity shows the waveform pulse
- Lock screen shows the full Live Activity card (the thing we're about to remove)

### Why this is tagged

We're about to remove the Live Activity lock screen presentation to reduce visual intrusion on the lock screen. If that change breaks background staying-alive behavior or brings back the "Start ST" nag, use this tag to roll back instantly.

---

## How to Roll Back

### Option 1: Checkout the tag (non-destructive, detached HEAD)

```bash
cd "/Users/dougallen/Desktop/stop-typing ios/StopTyping"
git checkout stable-v1-keyboard-always-active
```

Use this to test the known-good state without losing any work. You'll be in "detached HEAD" mode. To return to latest main:

```bash
git checkout main
```

### Option 2: Checkout the rollback branch (recommended)

```bash
cd "/Users/dougallen/Desktop/stop-typing ios/StopTyping"
git checkout stable/v1-keyboard-always-active
```

This puts you on a proper branch at the rollback commit. You can build, test, and even commit new work from here if needed.

### Option 3: Hard reset main (DESTRUCTIVE — only if you're sure)

**⚠️ This throws away all work after the rollback point.** Only use if everything since the tag is broken and you want to fully revert.

```bash
cd "/Users/dougallen/Desktop/stop-typing ios/StopTyping"
git checkout main
git reset --hard stable-v1-keyboard-always-active
git push --force-with-lease origin main
```

### Option 4: Revert specific commits (safest, preserves history)

If only certain commits broke things but you want to keep other work:

```bash
cd "/Users/dougallen/Desktop/stop-typing ios/StopTyping"
git log stable-v1-keyboard-always-active..HEAD --oneline
# identify the bad commit(s)
git revert <bad-commit-sha>
```

This creates a new commit that undoes the bad changes while preserving history.

---

## Verifying the Rollback Worked

After rolling back, test this exact sequence:

1. Build and run on iPhone from Xcode
2. Delete the app from the phone, reinstall, reboot phone
3. Open the app, complete onboarding
4. Activate the session (should land on activation overlay)
5. Go to Messages, open the Stop Typing keyboard
6. Verify you see the active toolbar with the mic button (NOT "Start ST")
7. Lock phone, wait 5+ minutes, unlock
8. Go back to Messages, tap the mic button → should start recording immediately
9. No "Start ST" prompt should appear at any point

If all 9 steps pass, the rollback is successful.

---

## Remote Backup

Both the tag and rollback branch are pushed to GitHub:

- Tag: `stable-v1-keyboard-always-active` at `https://github.com/ai-developers-dev/stop-typing-ios`
- Branch: `stable/v1-keyboard-always-active` at `https://github.com/ai-developers-dev/stop-typing-ios`

Even if your local machine is lost, you can re-fetch:

```bash
git fetch origin --tags
git fetch origin stable/v1-keyboard-always-active
```
