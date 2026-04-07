//
//  OverdueRowView.swift
//  PlanET
//
//  Created by SeungHyeon Lee on 1/27/26.
//

import SwiftUI
import WidgetKit // NEW
import UserNotifications

// MARK: overdue
struct OverdueRowView: View {
    let task: TaskItem
    var manager: TaskManager
    @State private var showEditSheet = false
    
    var body: some View {
        HStack {
            Button(action: { withAnimation { manager.toggleCompletion(for: task.id) }}) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3).foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            
            Text(task.title).foregroundStyle(.primary)
                .onTapGesture { showEditSheet = true }
            
            if task.recurrenceRule != nil {
                Image(systemName: "repeat").font(.caption).foregroundStyle(.blue)
            }
            Spacer()
            Text(task.deadline, style: .date)
                .font(.caption2).foregroundStyle(.red.opacity(0.8))
        }
        .padding(8)
        .background(Color.red.opacity(0.05))
        .cornerRadius(6)
        .contentShape(Rectangle())
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
