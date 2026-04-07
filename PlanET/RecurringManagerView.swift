//
//  RecurringManagerView.swift
//  PlanET
//
//  Created by SeungHyeon Lee on 1/27/26.
//

import SwiftUI

struct RecurringManagerView: View {
    @Bindable var manager: TaskManager
    @Environment(\.dismiss) var dismiss
    
    // Filter only recurring tasks
    var recurringTasks: [Binding<TaskItem>] {
        $manager.tasks.filter { $0.recurrenceRule.wrappedValue != nil && !$0.isCompleted.wrappedValue }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if recurringTasks.isEmpty {
                    Text("No recurring tasks found.")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ForEach(recurringTasks) { $task in
                        RecurringTaskRow(task: $task, manager: manager)
                    }
                }
            }
            .navigationTitle("Recurring Tasks")
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }
}

// MARK: - Smart Row Component
struct RecurringTaskRow: View {
    @Binding var task: TaskItem
    var manager: TaskManager
    
    // Internal state for the UI logic
    @State private var selectedMode: String = "daily"
    @State private var customDays: Set<Int> = [] // 1=Sun, 2=Mon...
    
    let days = [
        (1, "S"), (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title & Current Status
            HStack {
                Text(task.title).font(.headline)
                Spacer()
                Text("Next: \(task.deadline.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Picker
            HStack {
                Text("Repeat:")
                Spacer()
                Picker("Frequency", selection: $selectedMode) {
                    Text("Daily").tag("daily")
                    Text("Weekly").tag("weekly")
                    Text("Monthly").tag("monthly")
                    Text("Weekdays (M-F)").tag("weekdays")
                    Text("Weekends (S,S)").tag("weekend")
                    Text("Custom").tag("custom")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: selectedMode) {
                    updateRule()
                }
            }
            
            // Custom Day Buttons (Visible only if Custom)
            if selectedMode == "custom" {
                HStack(spacing: 8) {
                    ForEach(days, id: \.0) { dayVal, dayLabel in
                        Button(action: { toggleDay(dayVal) }) {
                            Text(dayLabel)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .frame(width: 32, height: 32)
                                .background(customDays.contains(dayVal) ? Color.green : Color.gray.opacity(0.2))
                                .foregroundStyle(customDays.contains(dayVal) ? .white : .primary)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 5)
            }
        }
        .padding(.vertical, 5)
        .onAppear {
            parseExistingRule()
        }
    }
    
    // MARK: - Logic Helpers
    
    // 1. Read the task's rule and set up the UI state
    private func parseExistingRule() {
        guard let rule = task.recurrenceRule else { return }
        
        if rule.hasPrefix("days:") {
            selectedMode = "custom"
            // Parse "days:2,4,6" into Set [2,4,6]
            let nums = rule.dropFirst(5).split(separator: ",").compactMap { Int($0) }
            customDays = Set(nums)
        } else {
            // Standard rules
            selectedMode = rule
        }
    }
    
    // 2. Handle Day Toggles
    private func toggleDay(_ day: Int) {
        if customDays.contains(day) {
            customDays.remove(day)
        } else {
            customDays.insert(day)
        }
        updateRule() // Save immediately
    }
    
    // 3. Build the rule string and save
    private func updateRule() {
        if selectedMode == "custom" {
            // Build "days:2,4,6" string
            if customDays.isEmpty {
                // If user unselects everything, fallback to weekly so it doesn't break
                task.recurrenceRule = "weekly"
            } else {
                let sortedDays = customDays.sorted().map { String($0) }.joined(separator: ",")
                task.recurrenceRule = "days:\(sortedDays)"
            }
        } else {
            // Simple rules (daily, weekly, etc)
            task.recurrenceRule = selectedMode
        }
        
        // Force save in manager
        manager.saveData()
    }
}
