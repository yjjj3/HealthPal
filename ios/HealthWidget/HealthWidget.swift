//
//  HealthWidget.swift
//  HealthWidget
//
//  Created by 楊昀儒 on 2025/12/27.
//

import WidgetKit
import SwiftUI

// MARK: - 資料結構
struct HealthEntry: TimelineEntry {
    let date: Date
    let bpSystolic: Int?
    let bpDiastolic: Int?
    let glucose: Int?
    let heartRate: Int?
    let lastUpdated: String?
    let bpTime: String?
    let glucoseTime: String?
}

// MARK: - Timeline Provider
struct HealthWidgetProvider: TimelineProvider {
    // 您的 App Group ID
    let appGroupId = "group.com.yunju.healthmanager"

    func placeholder(in context: Context) -> HealthEntry {
        HealthEntry(
            date: Date(),
            bpSystolic: 120,
            bpDiastolic: 80,
            glucose: 95,
            heartRate: 72,
            lastUpdated: "12/27 10:00",
            bpTime: nil,
            glucoseTime: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (HealthEntry) -> Void) {
        let entry = getEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HealthEntry>) -> Void) {
        let entry = getEntry()
        // 每 15 分鐘更新一次
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func getEntry() -> HealthEntry {
        let userDefaults = UserDefaults(suiteName: appGroupId)

        let bpSys = userDefaults?.integer(forKey: "bp_systolic")
        let bpDia = userDefaults?.integer(forKey: "bp_diastolic")
        let glucose = userDefaults?.integer(forKey: "glucose")
        let heartRate = userDefaults?.integer(forKey: "heart_rate")

        return HealthEntry(
            date: Date(),
            bpSystolic: bpSys == 0 ? nil : bpSys,
            bpDiastolic: bpDia == 0 ? nil : bpDia,
            glucose: glucose == 0 ? nil : glucose,
            heartRate: heartRate == 0 ? nil : heartRate,
            lastUpdated: userDefaults?.string(forKey: "last_updated"),
            bpTime: userDefaults?.string(forKey: "bp_time"),
            glucoseTime: userDefaults?.string(forKey: "glucose_time")
        )
    }
}

// MARK: - Widget 視圖
struct HealthWidgetEntryView: View {
    var entry: HealthEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - 小尺寸視圖
struct SmallWidgetView: View {
    var entry: HealthEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 標題
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                Text("健康數據")
                    .font(.caption)
                    .fontWeight(.semibold)
            }

            Spacer()

            // 血壓
            if let sys = entry.bpSystolic, let dia = entry.bpDiastolic {
                HStack(spacing: 4) {
                    Image(systemName: "heart.circle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text("\(sys)/\(dia)")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.bold)
                    Text("mmHg")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "heart.circle.fill")
                        .foregroundColor(.gray)
                        .font(.caption)
                    Text("--/--")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }

            // 血糖
            if let glucose = entry.glucose {
                HStack(spacing: 4) {
                    Image(systemName: "drop.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("\(glucose)")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.bold)
                    Text("mg/dL")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "drop.fill")
                        .foregroundColor(.gray)
                        .font(.caption)
                    Text("--")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // 更新時間
            if let updated = entry.lastUpdated {
                Text(updated)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("尚無數據")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .healthWidgetBackground()
    }
}

// MARK: - 中尺寸視圖
struct MediumWidgetView: View {
    var entry: HealthEntry

    var body: some View {
        HStack(spacing: 16) {
            // 左側：血壓
            VStack(alignment: .leading, spacing: 4) {
                Label("血壓", systemImage: "heart.circle.fill")
                    .font(.caption)
                    .foregroundColor(.red)

                if let sys = entry.bpSystolic, let dia = entry.bpDiastolic {
                    Text("\(sys)/\(dia)")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)
                    Text("mmHg")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let time = entry.bpTime {
                        Text(time)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("--/--")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("尚無數據")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            // 右側：血糖
            VStack(alignment: .leading, spacing: 4) {
                Label("血糖", systemImage: "drop.fill")
                    .font(.caption)
                    .foregroundColor(.orange)

                if let glucose = entry.glucose {
                    Text("\(glucose)")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)
                    Text("mg/dL")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let time = entry.glucoseTime {
                        Text(time)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("--")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("尚無數據")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .healthWidgetBackground()
    }
}

// MARK: - Widget 定義
struct HealthWidget: Widget {
    let kind: String = "HealthWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HealthWidgetProvider()) { entry in
            HealthWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("健康數據")
        .description("顯示最新的血壓和血糖數據")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - 預覽
@available(iOS 17.0, *)
#Preview(as: .systemSmall) {
    HealthWidget()
} timeline: {
    HealthEntry(date: Date(), bpSystolic: 120, bpDiastolic: 80, glucose: 95, heartRate: 72, lastUpdated: "12/27 10:00", bpTime: nil, glucoseTime: nil)
}

@available(iOS 17.0, *)
#Preview(as: .systemMedium) {
    HealthWidget()
} timeline: {
    HealthEntry(date: Date(), bpSystolic: 135, bpDiastolic: 85, glucose: 110, heartRate: 75, lastUpdated: "12/27 10:00", bpTime: "12/27 08:30", glucoseTime: "12/27 07:00")
}

private extension View {
    @ViewBuilder
    func healthWidgetBackground() -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(.fill.tertiary, for: .widget)
        } else {
            background(Color(uiColor: .tertiarySystemBackground))
        }
    }
}
