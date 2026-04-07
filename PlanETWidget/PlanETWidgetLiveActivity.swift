//
//  PlanETWidgetLiveActivity.swift
//  PlanETWidget
//
//  Created by SeungHyeon Lee on 1/27/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct PlanETWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct PlanETWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlanETWidgetAttributes.self) { context in
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

extension PlanETWidgetAttributes {
    fileprivate static var preview: PlanETWidgetAttributes {
        PlanETWidgetAttributes(name: "World")
    }
}

extension PlanETWidgetAttributes.ContentState {
    fileprivate static var smiley: PlanETWidgetAttributes.ContentState {
        PlanETWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: PlanETWidgetAttributes.ContentState {
         PlanETWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: PlanETWidgetAttributes.preview) {
   PlanETWidgetLiveActivity()
} contentStates: {
    PlanETWidgetAttributes.ContentState.smiley
    PlanETWidgetAttributes.ContentState.starEyes
}
