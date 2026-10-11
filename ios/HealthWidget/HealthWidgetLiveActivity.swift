//
//  HealthWidgetLiveActivity.swift
//  HealthWidget
//
//  Created by 楊昀儒 on 2025/12/27.
//

import ActivityKit
import WidgetKit
import SwiftUI

@available(iOS 16.1, *)
struct HealthWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

@available(iOS 16.1, *)
struct HealthWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HealthWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

@available(iOS 16.1, *)
extension HealthWidgetAttributes {
    fileprivate static var preview: HealthWidgetAttributes {
        HealthWidgetAttributes(name: "World")
    }
}

@available(iOS 16.1, *)
extension HealthWidgetAttributes.ContentState {
    fileprivate static var smiley: HealthWidgetAttributes.ContentState {
        HealthWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: HealthWidgetAttributes.ContentState {
         HealthWidgetAttributes.ContentState(emoji: "🤩")
     }
}

@available(iOS 17.0, *)
#Preview("Notification", as: .content, using: HealthWidgetAttributes.preview) {
   HealthWidgetLiveActivity()
} contentStates: {
    HealthWidgetAttributes.ContentState.smiley
    HealthWidgetAttributes.ContentState.starEyes
}
