//
//  TaskRowView.swift
//  PlanET
//
//  Created by SeungHyeon Lee on 1/27/26.
//

import SwiftUI
import WidgetKit // NEW
import UserNotifications

struct TaskRowView: View {
    let task: TaskItem
    var manager: TaskManager
    var backgroundColor: Color? = nil
    
    // Passed from parent
    var showAbsoluteDate: Bool = false
    @Environment(\.colorScheme) var scheme
    
    @State private var showEditSheet = false
    
    
    
    var body: some View {
        // WRAP EVERYTHING IN A BUTTON TO MAKE IT TAPPABLE ON iPHONE
        Button(action: { showEditSheet = true }) {
            HStack {
                // Circle Button (Independent tap logic)
                Button(action: { withAnimation { manager.toggleCompletion(for: task.id) }}) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(task.isCompleted ? .green : .secondary)
                }
                .buttonStyle(.plain) // Prevents row click from triggering this
                
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                
                if task.recurrenceRule != nil {
                    Image(systemName: "repeat").font(.caption).foregroundStyle(.blue)
                }
                
                Spacer()
                
                if task.isCompleted {
                    if let date = task.completedDate {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    // Display Logic
                    // If toggle ON AND time > 24 hours, show Date. Otherwise relative.
                    let timeUntil = task.deadline.timeIntervalSinceNow
                    if showAbsoluteDate && timeUntil > 86400 {
                        Text(task.deadline, format: .dateTime.month().day().hour().minute())
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text(task.deadline, style: .relative)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(8)
            .background(backgroundColor ?? manager.colorFor(category: task.category, scheme: scheme))
            .cornerRadius(6)
            .contentShape(Rectangle()) // Ensures the whole area is clickable
        }
        .buttonStyle(.plain) // Removes standard button flashing effect
        .sheet(isPresented: $showEditSheet) {
            EditTaskSheet(task: task, manager: manager)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
             Button(role: .destructive) {
                 withAnimation { manager.deleteTask(id: task.id) }
             } label: { Label("Delete", systemImage: "trash") }
             
             Button { showEditSheet = true } label: { Label("Edit", systemImage: "pencil") }.tint(.orange)
         }
         .sheet(isPresented: $showEditSheet) {
             EditTaskSheet(task: task, manager: manager)
         }
    }
}
