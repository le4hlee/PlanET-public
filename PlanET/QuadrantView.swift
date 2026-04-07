//
//  QuadrantView.swift
//  PlanET
//
//  Created by SeungHyeon Lee on 1/27/26.
//

import SwiftUI
import WidgetKit // NEW
import UserNotifications

// MARK: quadrant
struct QuadrantView: View {
    let quadrant: TimeQuadrant
    var manager: TaskManager
    
    var showAbsoluteDates: Bool
    
    
    @State private var isExpanded: Bool = true
    
    @State private var expandedGroups: Set<String> = []
    
    @Environment(\.colorScheme) var scheme
    @Environment(\.horizontalSizeClass) var sizeClass
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // header of quadrant name
            HStack {
                Text(quadrant.name).font(.headline)
                Spacer()
                Button(action: { withAnimation { isExpanded.toggle() }}) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.thickMaterial)
            
            // content
            if isExpanded {
//                TimelineView(.periodic(from: .now, by: 1.0)) { context in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 15) {
                            ForEach(quadrant.buckets) { bucket in
                                let tasks = manager.getTasks(for: bucket)
                                
                                let isEmpty = tasks.isEmpty
                                
                                let groupedTasks = Dictionary(grouping: tasks, by: { $0.category ?? "Uncategorized" })
                                                                
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(bucket.name).font(.caption).fontWeight(.bold).textCase(.uppercase).foregroundStyle(.secondary)
                                    
                                    if !isEmpty {
                                        VStack(spacing: 8) {
                                            
                                            // 1. Render Categories (if they have >= 3 items in THIS bucket)
                                            ForEach(groupedTasks.keys.sorted(), id: \.self) { key in
                                                if key != "Uncategorized", let items = groupedTasks[key] {
                                                    let color = manager.colorFor(category: key, scheme: scheme)
                                                    
                                                    // CONDITIONAL: Only collapse if >= 3 items. Otherwise just list them colored.
                                                    if items.count >= 3 {
                                                        // Render as Toggle Folder
                                                        GroupHeaderView(
                                                            title: key,
                                                            color: color,
                                                            count: items.count,
                                                            isExpanded: Binding(
                                                                get: { expandedGroups.contains(key) },
                                                                set: { isExpanded in
                                                                    if isExpanded { expandedGroups.insert(key) }
                                                                    else { expandedGroups.remove(key) }
                                                                }
                                                            )
                                                        )
                                                        
                                                        if expandedGroups.contains(key) {
                                                            ForEach(items) { task in
                                                                TaskRowView(task: task, manager: manager, backgroundColor: color.opacity(0.5), showAbsoluteDate: showAbsoluteDates)
                                                                                                                                    .padding(.leading, 10)
                                                            }
                                                        }
                                                    } else {
                                                        // Render as individual items (but colored!)
                                                        ForEach(items) { task in
                                                            TaskRowView(task: task, manager: manager, showAbsoluteDate: showAbsoluteDates)
                                                        }
                                                    }
                                                }
                                            }
                                            
                                            // 2. Render Uncategorized
                                            if let ungrouped = groupedTasks["Uncategorized"] {
                                                ForEach(ungrouped) { task in
                                                    TaskRowView(task: task, manager: manager, showAbsoluteDate: showAbsoluteDates)
                                                }
                                            }
                                        }
                                        .animation(.default, value: tasks)
                                    } else {
                                        Rectangle().fill(Color.secondary.opacity(0.1)).frame(height: 2)
                                    }
                                }
                                .opacity(tasks.isEmpty ? 0.3 : 1.0)
                            }
                        }
                        .padding()
                    }
//                }
                .frame(maxHeight: sizeClass == .compact ? 300 : .infinity)
            }
        }
        .background(.regularMaterial)
        .cornerRadius(12)
        .frame(maxWidth: .infinity)
        .frame(height: (sizeClass == .compact && isExpanded) ? 300 : nil)
        .frame(maxHeight: (sizeClass != .compact && isExpanded) ? .infinity : nil)
    }
}
