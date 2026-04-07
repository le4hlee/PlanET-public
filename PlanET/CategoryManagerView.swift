//
//  CategoryManagerView.swift
//  PlanET
//
//  Created by SeungHyeon Lee on 1/27/26.
//

import SwiftUI
import WidgetKit // NEW
import UserNotifications

// MARK: Category
struct CategoryManagerView: View {
    @Bindable var manager: TaskManager
    @Environment(\.dismiss) var dismiss
    
    @Environment(\.colorScheme) var scheme
    
    
    @State private var newCategoryName = ""
    
    // Sheet States
    @State private var showAssignmentSheet = false
    @State private var selectedCategoryForEdit = ""
    
    // Rename States
    @State private var categoryToRename: String? = nil
    @State private var renameInput: String = ""
    
    var body: some View {
        NavigationStack {
            List {
                Section("Add New Category") {
                    HStack {
                        TextField("e.g., 'Study', 'Gym'", text: $newCategoryName)
                        Button("Add") {
                            if !newCategoryName.isEmpty {
                                selectedCategoryForEdit = newCategoryName
                                showAssignmentSheet = true
                                newCategoryName = ""
                            }
                        }
                        .disabled(newCategoryName.isEmpty)
                        .buttonStyle(.borderedProminent)
                    }
                }
                
                Section("Active Categories") {
                    let categories = manager.getAllCategories()
                    if categories.isEmpty {
                        Text("No categories yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(categories, id: \.self) { cat in
                            // WRAP IN BUTTON FOR TAP-TO-EDIT
                            Button(action: {
                                selectedCategoryForEdit = cat
                                showAssignmentSheet = true
                            }) {
                                HStack {
                                    Circle().fill(manager.colorFor(category: cat, scheme: scheme)).frame(width: 10, height: 10)
                                    Text(cat).foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(manager.tasks.filter { $0.category == cat }.count) tasks")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button("Rename") {
                                    categoryToRename = cat
                                    renameInput = cat
                                }.tint(.orange)
                            }
                            // NEW: Delete Action
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    withAnimation {
                                        manager.deleteCategory(cat)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Manage Categories")
            .toolbar {
                Button("Done") { dismiss() }
            }
            // Sheet handles both NEW and EDITING
            .sheet(isPresented: $showAssignmentSheet) {
                CategoryAssignmentSheet(manager: manager, categoryName: selectedCategoryForEdit)
            }
            .alert("Rename Category", isPresented: Binding(
                get: { categoryToRename != nil },
                set: { if !$0 { categoryToRename = nil } }
            )) {
                TextField("New Name", text: $renameInput)
                Button("Cancel", role: .cancel) { }
                Button("Rename") {
                    if let oldName = categoryToRename {
                        manager.renameCategory(from: oldName, to: renameInput)
                    }
                }
            } message: {
                Text("Enter a new name for this category.")
            }
        }
    }
}

struct CategoryAssignmentSheet: View {
    var manager: TaskManager
    var categoryName: String
    @Environment(\.dismiss) var dismiss
    
    // Tracks which tasks are selected
    @State private var selectedTaskIDs: Set<UUID> = []
    
    // Notification State
    @State private var isNotificationEnabled: Bool = true
    var body: some View {
        NavigationStack {
            VStack {
                Toggle("Enable Notifications for '\(categoryName)'", isOn: $isNotificationEnabled)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)

                Text("Manage tasks for '\(categoryName)'")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top)
                
                List {
                    // Filter: Show tasks that are ALREADY in this category OR are Uncategorized
                    // We don't show tasks belonging to OTHER categories to keep it clean.
                    let candidates = manager.tasks.filter {
                        !$0.isCompleted && ($0.category == categoryName || $0.category == nil)
                    }.sorted {
                        // Sort: Tasks already in this category go to top
                        ($0.category == categoryName ? 0 : 1) < ($1.category == categoryName ? 0 : 1)
                    }
                    
                    if candidates.isEmpty {
                        Text("No available tasks")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(candidates) { task in
                            HStack {
                                Image(systemName: selectedTaskIDs.contains(task.id) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(selectedTaskIDs.contains(task.id) ? .blue : .gray)
                                    .font(.title3)
                                
                                Text(task.title)
                                Spacer()
                                
                                // Visual cue if it's already in the category
                                if task.category == categoryName {
                                    Text("Current")
                                        .font(.caption2)
                                        .padding(4)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(4)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedTaskIDs.contains(task.id) {
                                    selectedTaskIDs.remove(task.id)
                                } else {
                                    selectedTaskIDs.insert(task.id)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // 1. Update Membership
                        manager.updateCategoryMembership(category: categoryName, finalSelectedIDs: selectedTaskIDs)
                        
                        // 2. Update Notification Prefs
                        manager.toggleCategoryNotification(for: categoryName, isEnabled: isNotificationEnabled)
                        
                        dismiss()
                    }
                }
            }
            .onAppear {
                // 1. Pre-select tasks that are ALREADY in this category
                // 2. Pre-select tasks that match the pattern (if creating new)
                let candidates = manager.tasks.filter { !$0.isCompleted }
                for task in candidates {
                    // If editing existing:
                    if task.category == categoryName {
                        selectedTaskIDs.insert(task.id)
                    }
                    // If creating new (category doesn't exist on tasks yet) but matches pattern:
                    else if task.category == nil && task.title.localizedCaseInsensitiveContains(categoryName) {
                        selectedTaskIDs.insert(task.id)
                    }
                }
                
                // Load Notification Pref (Default to true if missing)
                isNotificationEnabled = manager.categoryNotificationPrefs[categoryName] ?? true
            }
        }
    }
}
