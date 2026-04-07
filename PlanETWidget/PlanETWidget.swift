//
//  PlanETWidget.swift
//  PlanETWidget
//
//  Created by SeungHyeon Lee on 1/27/26.
//
import WidgetKit
import SwiftUI

// 1. Lightweight Model for Widget (Must match TaskItem JSON structure)
struct WidgetTaskItem: Codable, Identifiable {
    let id: UUID
    let title: String
    let deadline: Date
    let isCompleted: Bool
    let category: String?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), tasks: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let tasks = loadTasks()
        let entry = SimpleEntry(date: Date(), tasks: tasks)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let tasks = loadTasks()
        let entry = SimpleEntry(date: Date(), tasks: tasks)
        
        // Refresh every 15 minutes automatically
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    func loadTasks() -> [WidgetTaskItem] {
        // !!! REPLACE WITH YOUR EXACT APP GROUP ID !!!
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.leahlee.PlanET")?.appendingPathComponent("SavedTasks.json") else { return [] }
        
        do {
            let data = try Data(contentsOf: url)
            let tasks = try JSONDecoder().decode([WidgetTaskItem].self, from: data)
            // Filter completed and sort by deadline
            return tasks.filter { !$0.isCompleted }.sorted { $0.deadline < $1.deadline }
        } catch {
            return []
        }
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let tasks: [WidgetTaskItem]
}
struct PlanETWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("UPCOMING")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                Spacer()
                // Show count if we have more tasks than fit
                if entry.tasks.count > showLimit {
                    Text("+\(entry.tasks.count - showLimit)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 6)
            
            if entry.tasks.isEmpty {
                Spacer()
                Text("All Caught Up! 🎉")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                // Task List
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(entry.tasks.prefix(showLimit))) { task in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            // Urgency Dot
                            Circle()
                                .fill(colorForTask(task))
                                .frame(width: 6, height: 6)
                                .offset(y: 1)
                            
                            // Title
                            Text(task.title)
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .strikethrough(task.isCompleted)
                            
                            Spacer()
                            
                            // Time
                            Text(task.deadline, style: .relative)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            Spacer()
        }
        .padding()
        .containerBackground(for: .widget) {
            Color("Background") // Ensure you have this color in Assets, or use Color.white/black
        }
    }
    
    // Determine how many items to show based on widget size
    var showLimit: Int {
        switch family {
        case .systemSmall: return 4
        case .systemMedium: return 5
        default: return 10
        }
    }
    
    func colorForTask(_ task: WidgetTaskItem) -> Color {
        // Red if overdue or due within 1 hour
        if task.deadline < Date().addingTimeInterval(3600) {
            return .red
        }
        // Category-based colors logic could go here if you passed color data
        return .blue
    }
}

@main
struct PlanETWidget: Widget {
    let kind: String = "PlanETWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PlanETWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Urgent Tasks")
        .description("Shows your top upcoming tasks.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
