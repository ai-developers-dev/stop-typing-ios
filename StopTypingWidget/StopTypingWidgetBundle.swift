//
//  StopTypingWidgetBundle.swift
//  StopTypingWidget
//
//  Created by Doug Allen on 4/9/26.
//

import WidgetKit
import SwiftUI

@main
struct StopTypingWidgetBundle: WidgetBundle {
    var body: some Widget {
        StopTypingWidget()
        StopTypingWidgetControl()
        StopTypingWidgetLiveActivity()
    }
}
