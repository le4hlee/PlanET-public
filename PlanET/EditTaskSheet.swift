//
//  EditTaskSheet.swift
//  PlanET
//
//  Created by SeungHyeon Lee on 1/27/26.
//

import SwiftUI
import WidgetKit // NEW
import UserNotifications

struct EditTaskSheet: View {
    @Environment(\.dismiss) var dismiss
    var task: TaskItem
    var manager: TaskManager
    
    @State private var editTitle: String = ""
    @State private var editDate: Date = Date()
    
    @State private var notificationsEnabled: Bool = true
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Task Name", text: $editTitle)
                DatePicker("Deadline", selection: $editDate)
                
                Section {
                    Toggle("Remind Me", isOn: $notificationsEnabled)
                } footer: {
                    if let cat = task.category, let catEnabled = manager.categoryNotificationPrefs[cat], !catEnabled {
                        Text("Note: Notifications for category '\(cat)' are currently disabled.")
                            .foregroundStyle(.orange)
                    }
                }
                
                Section {
                    Button("Delete Task", role: .destructive) {
                        manager.deleteTask(id: task.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Save the new state
                        var updatedTask = task
                        updatedTask.isNotificationEnabled = notificationsEnabled
                        manager.updateTask(updatedTask, newTitle: editTitle, newDate: editDate)
                        dismiss()
                    }
                }
            }
            .onAppear {
                editTitle = task.title
                editDate = task.deadline
                notificationsEnabled = task.isNotificationEnabled ?? true
            }
        }
    }
}
