//
//  ContentView.swift
//  PlanET
//
//  Created by SeungHyeon Lee on 1/19/26.
//

import SwiftUI
import WidgetKit
import UserNotifications

internal import UniformTypeIdentifiers

// MARK: - 1. Data Models
struct TaskItem: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var deadline: Date
    var isCompleted: Bool
    var completedDate: Date?
    
    var recurrenceRule: String?
    var hasGeneratedNext: Bool
    
    var category: String?
    
    var isNotificationEnabled: Bool?
    
    init(id: UUID = UUID(), title: String, deadline: Date, isCompleted: Bool = false, completedDate: Date? = nil, recurrenceRule: String? = nil, hasGeneratedNext: Bool = false, category: String? = nil, isNotificationEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.deadline = deadline
        self.isCompleted = isCompleted
        self.completedDate = completedDate
        self.recurrenceRule = recurrenceRule
        self.hasGeneratedNext = hasGeneratedNext
        self.category = category
        self.isNotificationEnabled = isNotificationEnabled
    }
}

struct TimeBucket: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var timeLimitInSeconds: TimeInterval
}

struct TimeQuadrant: Identifiable {
    let id = UUID()
    let name: String
    var buckets: [TimeBucket]
}



// MARK: Extension for color hex
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - 3. UI Components

struct ContentView: View {
    @State private var manager = TaskManager()
    @State private var inputText = ""
    @State private var showHistory = false
    @Environment(\.horizontalSizeClass) var sizeClass
    
    // Toggle State
    @AppStorage("showAbsoluteDates") private var showAbsoluteDates: Bool = false
    
    // Theme
    @AppStorage("userTheme") private var userTheme: String = "system"
    @Environment(\.colorScheme) private var systemScheme
    
    // Sheet & Alert States
    @State private var showDeleteConfirmation = false
    @State private var showCategoryAlert = false
    @State private var suggestedCategory: String = ""
    @State private var showCategoryManager = false
    @State private var showRecurringManager = false
    
    // Import States
    @State private var isImporting = false
    @State private var showImportAlert = false
    @State private var importMessage = ""
    
    var effectiveScheme: ColorScheme? {
        if userTheme == "dark" { return .dark }
        if userTheme == "light" { return .light }
        return nil
    }
    
    var currentIcon: String {
        if userTheme == "system" { return systemScheme == .dark ? "moon.fill" : "sun.max.fill" }
        else { return userTheme == "dark" ? "moon.fill" : "sun.max.fill" }
    }
    
    // MARK: - Main Body
    var body: some View {
        Group {
            if sizeClass == .compact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .preferredColorScheme(effectiveScheme)
        .background(Color("Background")) // Ensure this color exists in Assets
        
        // --- MODIFIERS (Kept in main body) ---
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("Import Result", isPresented: $showImportAlert) {
            Button("OK", role: .cancel) { }
        } message: { Text(importMessage) }
        
        .sheet(isPresented: $showCategoryManager) { CategoryManagerView(manager: manager) }
        .sheet(isPresented: $showRecurringManager) { RecurringManagerView(manager: manager) }
        
        .alert("Group Tasks?", isPresented: $showCategoryAlert) {
            Button("Group as '\(suggestedCategory)'") { manager.applyCategory(suggestedCategory) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("We noticed multiple tasks starting with '\(suggestedCategory)'. Would you like to group them together?")
        }
        .alert("Delete Everything?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) { withAnimation { manager.deleteAllTasks() } }
        } message: {
            Text("This will permanently erase all active, completed, and overdue tasks.")
        }
    }
    
    // MARK: - Broken Down Views
    
    // 1. iPhone Layout
    var iPhoneLayout: some View {
        TabView {
            VStack(spacing: 0) {
                // SINGLE HEADER ROW
                HStack(spacing: 12) { // Tighter spacing to fit everything
                    Text("Tasks")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        // Allow title to shrink slightly if screen is very narrow
                        .minimumScaleFactor(0.8)
                    
                    Spacer()
                    
                    // The Action Buttons (Now in the same row)
                    headerButtons
                }
                .padding(.horizontal)
                .padding(.top)
                .padding(.bottom, 10)
                
                inputBar
                
                mainTaskScrollView
                    .onTapGesture { hideKeyboard() }
            }
            .tabItem { Label("Tasks", systemImage: "list.bullet") }
            
            historyView.tabItem { Label("History", systemImage: "clock") }
        }
    }
    
    // MARK: 2. iPad / Mac Layout
    var iPadLayout: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack {
                Button(action: { withAnimation { showHistory.toggle() }}) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title2).padding().foregroundStyle(showHistory ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Sidebar Actions
                Menu {
                    Button("Import") { isImporting = true }
                    ShareLink("Export", item: manager.exportURL)
                } label: {
                    Image(systemName: "arrow.up.arrow.down.square").font(.title2).foregroundStyle(.primary)
                }
                .menuStyle(.borderlessButton)
                .padding(.bottom, 20)
                
                Button(action: { showAbsoluteDates.toggle() }) {
                    Image(systemName: showAbsoluteDates ? "calendar" : "hourglass").font(.title2).foregroundStyle(.primary)
                }
                .buttonStyle(.plain).padding(.bottom, 20)

                Menu {
                    Button("Recurring") { showRecurringManager = true }
                    Button("Categories") { showCategoryManager = true }
                } label: {
                    Image(systemName: "slider.horizontal.3").font(.title2).foregroundStyle(.primary)
                }
                .menuStyle(.borderlessButton)
                .padding(.bottom, 20)

                Button(action: { showDeleteConfirmation = true }) {
                    Image(systemName: "trash").font(.title2).foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain).padding(.bottom, 20)
                
                Button(action: {
                    withAnimation {
                        if userTheme == "system" { userTheme = (systemScheme == .dark) ? "light" : "dark" }
                        else { userTheme = (userTheme == "dark") ? "light" : "dark" }
                    }
                }) {
                    Image(systemName: currentIcon).font(.title2).foregroundStyle(.primary)
                }
                .buttonStyle(.plain).padding(.bottom, 10)
            }
            .background(.regularMaterial)
            .zIndex(2)
            
            // History Drawer
            if showHistory {
                historyView
                    .frame(width: 320)
                    .transition(.move(edge: .leading))
                    .zIndex(1)
            }
            
            // Main Content
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 8) {
                        QuadrantView(quadrant: manager.quadrants[0], manager: manager, showAbsoluteDates: showAbsoluteDates)
                        QuadrantView(quadrant: manager.quadrants[2], manager: manager, showAbsoluteDates: showAbsoluteDates)
                    }
                    .frame(maxHeight: .infinity)
                    VStack(spacing: 8) {
                        QuadrantView(quadrant: manager.quadrants[1], manager: manager, showAbsoluteDates: showAbsoluteDates)
                        QuadrantView(quadrant: manager.quadrants[3], manager: manager, showAbsoluteDates: showAbsoluteDates)
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(8)
                inputBar
            }
            .onTapGesture { hideKeyboard() }
        }
    }
    
    // 3. Reusable Components
    
    var headerButtons: some View {
        Group {
            // 1. DATA GROUP (Import/Export)
            Menu {
                Button(action: { isImporting = true }) {
                    Label("Import Tasks", systemImage: "square.and.arrow.down")
                }
                ShareLink(item: manager.exportURL) {
                    Label("Export Tasks", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down.square")
                    .font(.title2)
            }
            
            // 2. MANAGE GROUP (Categories/Recurring)
            Menu {
                Button(action: { showRecurringManager = true }) {
                    Label("Recurring Tasks", systemImage: "repeat")
                }
                Button(action: { showCategoryManager = true }) {
                    Label("Categories", systemImage: "tag")
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2)
            }
            
            // 3. CALENDAR TOGGLE (Date View)
            Button(action: { showAbsoluteDates.toggle() }) {
                Image(systemName: showAbsoluteDates ? "calendar" : "hourglass")
                    .font(.title2)
            }
            
            // 4. DELETE ALL
            Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                Image(systemName: "trash.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
            }
        }
    }
    
    var mainTaskScrollView: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(manager.quadrants) { quadrant in
                    QuadrantView(quadrant: quadrant, manager: manager, showAbsoluteDates: showAbsoluteDates)
                }
            }
            .padding()
        }
    }
    
    var inputBar: some View {
        HStack {
            TextField("Try: 'Every Monday 5/23 noon', 'Gym daily'", text: $inputText)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .onSubmit {
                    handleSubmit()
                }
            
            Button(action: { handleSubmit() }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title).foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(.bar)
    }
    
    var historyView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("History").font(.headline).padding().frame(maxWidth: .infinity, alignment: .leading).background(.ultraThinMaterial)
            
            ScrollView {
                VStack(spacing: 20) {
                    let overdue = manager.getOverdueTasks()
                    if !overdue.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Overdue").font(.caption).fontWeight(.bold).foregroundStyle(.red).padding(.horizontal, 5)
                            ForEach(overdue) { task in
                                OverdueRowView(task: task, manager: manager)
                            }
                        }
                        .animation(.default, value: overdue)
                    }
                    
                    let completed = manager.getCompletedTasks()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Completed").font(.caption).fontWeight(.bold).foregroundStyle(.secondary).padding(.horizontal, 5)
                        if completed.isEmpty {
                            Text("No completed tasks").font(.caption).foregroundStyle(.secondary).padding(.leading, 5)
                        } else {
                            ForEach(completed) { task in
                                TaskRowView(task: task, manager: manager)
                            }
                        }
                    }
                    .animation(.default, value: completed)
                }
                .padding()
            }
        }
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Actions
    
    func handleSubmit() {
        manager.addTask(from: inputText)
        if let pattern = manager.checkForNewCategoryPattern() {
            suggestedCategory = pattern
            showCategoryAlert = true
        }
        inputText = ""
    }
    
    func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let selectedFile: URL = try result.get().first else { return }
            let count = try manager.importTasks(from: selectedFile)
            importMessage = "Successfully restored \(count) tasks."
            showImportAlert = true
        } catch {
            importMessage = "Failed to import: \(error.localizedDescription)"
            showImportAlert = true
        }
    }
}

// NEW: Helper to close keyboard
#if canImport(UIKit)
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif

// MARK: COLOR
extension Color {
    func toHex() -> String? {
        guard let components = cgColor?.components, components.count >= 3 else {
            return nil
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
    }
    
    var hsba: (hue: Double, saturation: Double, brightness: Double, alpha: Double) {
        // Fallback for SwiftUI colors that don't expose components easily
        // Note: This is a simplification for the generator logic
        return (0,0,0,0)
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 600)
}
