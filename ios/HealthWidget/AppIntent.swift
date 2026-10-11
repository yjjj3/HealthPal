//
//  AppIntent.swift
//  HealthWidget
//
//  Created by 楊昀儒 on 2025/12/27.
//

import WidgetKit
import AppIntents

@available(iOS 17.0, *)
struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Configuration" }
    static var description: IntentDescription { "This is an example widget." }

    // An example configurable parameter.
    @Parameter(title: "Favorite Emoji", default: "😃")
    var favoriteEmoji: String
}
