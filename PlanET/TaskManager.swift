//
//  TaskManager.swift
//  PlanET
//
//  Created by SeungHyeon Lee on 1/27/26.
//

import SwiftUI
import WidgetKit // NEW
import UserNotifications

// MARK: - 2. Logic Center (ViewModel)
@Observable
class TaskManager {
    var tasks: [TaskItem] = []
    var allBuckets: [TimeBucket] = []
    var numberMapping: [String: Int] = [:]
    
    var categoryColors: [String: String] = [:]

    // Store Category Notification Preferences (Category Name -> IsEnabled)
    var categoryNotificationPrefs: [String: Bool] = [:]
    
    // NEW: Path for prefs
    private var prefsPath: URL { rootPath.appendingPathComponent("CategoryPrefs.json") }
    
    
//    private var sharedContainerURL: URL {
//        // REPLACE WITH YOUR GROUP ID FROM STEP 1
//        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.leah.PlanET")!
//    }
    
    // MARK: legacyDocURL
    
    // 1. The OLD private path (Where your tasks are NOW)
    private var legacyDocURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    // MARK: sharedContainerURL
    
    // 2. The NEW shared path (Where Widget needs them)
    // IMPORTANT: Replace "group.com.yourname.PlanET" with your ACTUAL App Group ID from Xcode
    private var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.leah.PlanET")!
    }
    
    // MARK: rootPath, savePath, colorPath
    
    // 3. Dynamic Path Resolver
    private var rootPath: URL {
        // If App Group works, use it. Otherwise fall back to private (legacy)
        return sharedContainerURL ?? legacyDocURL
    }

    private let savePath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("SavedTasks.json")
    private let colorPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("CategoryColors.json")
    
    
    let timeKeywords: [String: Int] = [
        "morning": 8, "noon": 12, "afternoon": 14, "dinner": 18, "tonight": 23
    ]
    
    let monthMap: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3,
        "april": 4, "apr": 4, "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7,
        "august": 8, "aug": 8, "september": 9, "sep": 9, "sept": 9, "october": 10, "oct": 10,
        "november": 11, "nov": 11, "december": 12, "dec": 12
    ]
    
    var quadrants: [TimeQuadrant] = [
        TimeQuadrant(name: "Hours", buckets: [
            TimeBucket(name: "1 hr", timeLimitInSeconds: 3600),
            TimeBucket(name: "3 hr", timeLimitInSeconds: 10800),
            TimeBucket(name: "6 hr", timeLimitInSeconds: 21600),
            TimeBucket(name: "12 hr", timeLimitInSeconds: 43200)
        ]),
        TimeQuadrant(name: "Days", buckets: [
            TimeBucket(name: "1 day", timeLimitInSeconds: 86400),
            TimeBucket(name: "3 days", timeLimitInSeconds: 259200),
            TimeBucket(name: "7 days", timeLimitInSeconds: 604800)
        ]),
        TimeQuadrant(name: "Months", buckets: [
            TimeBucket(name: "1 month", timeLimitInSeconds: 2_592_000),
            TimeBucket(name: "3 months", timeLimitInSeconds: 7_776_000),
            TimeBucket(name: "6 months", timeLimitInSeconds: 15_552_000),
            TimeBucket(name: "12 months", timeLimitInSeconds: 31_104_000)
        ]),
        TimeQuadrant(name: "Years", buckets: [
            TimeBucket(name: "1 year", timeLimitInSeconds: 31_536_000),
            TimeBucket(name: "3 years", timeLimitInSeconds: 94_608_000),
            TimeBucket(name: "5 years", timeLimitInSeconds: 157_680_000),
            TimeBucket(name: "10 years", timeLimitInSeconds: 315_360_000)
        ])
    ]
    
    init() {
        self.allBuckets = quadrants.flatMap { $0.buckets }.sorted { $0.timeLimitInSeconds < $1.timeLimitInSeconds }
        setupNumberMapping()
        migrateLegacyData()
//                loadData()
        loadData()
        requestNotificationPermission()
    }
    
    // MARK: - Notifications
    // MARK: requestNotificationPermission
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("Notification permission granted.")
            }
        }
    }

    // MARK: scheduleNotification
    func scheduleNotification(for task: TaskItem) {
        cancelNotification(for: task)
        
        // 1. Basic Checks (Completed or Past)
        if task.isCompleted || task.deadline < Date() { return }
        
        // 2. CHECK: Is Task Level Notification Enabled? (Default to true if nil)
        guard task.isNotificationEnabled ?? true else { return }
        
        // 3. CHECK: Is Category Level Notification Enabled?
        if let cat = task.category {
            // If category is set to false in prefs, return. Default is true.
            if let isCatEnabled = categoryNotificationPrefs[cat], !isCatEnabled {
                return
            }
        }
        
        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = "This task is due now."
        content.sound = .default
        
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: task.deadline)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(identifier: task.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: cancelNotification
    func cancelNotification(for task: TaskItem) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [task.id.uuidString])
    }
    
    // MARK: ToggleCategoryNotif
    func toggleCategoryNotification(for category: String, isEnabled: Bool) {
        categoryNotificationPrefs[category] = isEnabled
        
        // Re-evaluate notifications for all tasks in this category
        for task in tasks where task.category == category {
            if isEnabled {
                scheduleNotification(for: task)
            } else {
                cancelNotification(for: task)
            }
        }
        saveData()
    }

    // MARK: - Migration Logic (Auto-Restore)
    // MARK: migrateLegacyData
    func migrateLegacyData() {
        // If we DO have a shared container...
        guard let sharedURL = sharedContainerURL else { return }
        
        let newTasksURL = sharedURL.appendingPathComponent("SavedTasks.json")
        let oldTasksURL = legacyDocURL.appendingPathComponent("SavedTasks.json")
        
        let newColorsURL = sharedURL.appendingPathComponent("CategoryColors.json")
        let oldColorsURL = legacyDocURL.appendingPathComponent("CategoryColors.json")
        
        let fm = FileManager.default
        
        // 1. Move Tasks
        // If NEW file doesn't exist, but OLD one does -> Copy it over
        if !fm.fileExists(atPath: newTasksURL.path) && fm.fileExists(atPath: oldTasksURL.path) {
            try? fm.copyItem(at: oldTasksURL, to: newTasksURL)
            print("MIGRATION: Moved Tasks to Shared Group")
        }
        
        // 2. Move Colors
        if !fm.fileExists(atPath: newColorsURL.path) && fm.fileExists(atPath: oldColorsURL.path) {
            try? fm.copyItem(at: oldColorsURL, to: newColorsURL)
            print("MIGRATION: Moved Colors to Shared Group")
        }
    }
    
    // MARK: - Export Logic exportURL
    // Creates a temporary file URL for the Share Sheet to use
    var exportURL: URL {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("PlanET_Backup.json")
        do {
            let data = try JSONEncoder().encode(tasks)
            try data.write(to: tempURL)
            return tempURL
        } catch {
            return savePath // Fallback
        }
    }
    
    // MARK: - Import/Restore Logic
    
    // MARK: importTasks
    // Returns the number of tasks successfully added
    func importTasks(from url: URL) throws -> Int {
        // 1. Gain permission to read the external file
        guard url.startAccessingSecurityScopedResource() else {
            throw URLError(.noPermissionsToReadFile)
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        // 2. Decode the data
        let data = try Data(contentsOf: url)
        let importedTasks = try JSONDecoder().decode([TaskItem].self, from: data)
        
        // 3. Merge Logic (Prevent Duplicates)
        var addedCount = 0
        let existingIDs = Set(tasks.map { $0.id })
        
        for task in importedTasks {
            // Only add if we don't already have this Task ID
            if !existingIDs.contains(task.id) {
                tasks.append(task)
                addedCount += 1
                
                // If the imported task has a category, make sure we have a color for it
                if let cat = task.category {
                    _ = colorFor(category: cat, scheme: .light) // Forces generation if missing
                }
            }
        }
        
        // 4. Save and return count
        if addedCount > 0 {
            saveData()
        }
        return addedCount
    }
    
    // MARK: saveData
    func saveData() {
        do {
            let taskData = try JSONEncoder().encode(tasks)
            try taskData.write(to: savePath, options: [.atomic, .completeFileProtection])
            
            // Save Colors separate so they persist even if tasks are deleted
            let colorData = try JSONEncoder().encode(categoryColors)
            try colorData.write(to: colorPath, options: [.atomic, .completeFileProtection])
            
            // Save Category Prefs
            let prefsData = try JSONEncoder().encode(categoryNotificationPrefs)
            try prefsData.write(to: prefsPath, options: [.atomic, .completeFileProtection])
            
            WidgetCenter.shared.reloadAllTimelines()
            
        } catch { print("Save error: \(error)") }
    }
    
    // MARK: loadData
    func loadData() {
        do {
            let data = try Data(contentsOf: savePath)
            tasks = try JSONDecoder().decode([TaskItem].self, from: data)
            
            // organize existing tasks
            retroactiveCategorize()
        } catch { tasks = [] }
        do {
            let colorData = try Data(contentsOf: colorPath)
            categoryColors = try JSONDecoder().decode([String: String].self, from: colorData)
        } catch { categoryColors = [:] }
        
        // Load Category Prefs
        do {
            let prefsData = try Data(contentsOf: prefsPath)
            categoryNotificationPrefs = try JSONDecoder().decode([String: Bool].self, from: prefsData)
        } catch { categoryNotificationPrefs = [:] }
        
        retroactiveCategorize()
        
    }
    
    
    // MARK: setupNumberMapping
    func setupNumberMapping() {
        var base: [String: Int] = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15]
        let higherNumbers: [String: Int] = ["sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "a": 1, "an": 1]
        base.merge(higherNumbers) { (current, _) in current }
        self.numberMapping = base
        
        let tens = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50]
        let ones = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9]
        for (tKey, tVal) in tens {
            for (oKey, oVal) in ones {
                self.numberMapping["\(tKey) \(oKey)"] = tVal + oVal
                self.numberMapping["\(tKey)-\(oKey)"] = tVal + oVal
            }
        }
    }
    
    // MARK: - category and color logic
    
    // MARK: retroactiveCategorize
    // Scans all tasks and assigns them to categories if they match existing groups
    private func retroactiveCategorize() {
        // 1. Find all categories currently in use
        let existingCategories = Set(tasks.compactMap { $0.category })
        var hasChanges = false
        
        // 2. Check every task that DOESN'T have a category
        for index in tasks.indices {
            if tasks[index].category == nil {
                // 3. If it starts with the name of an existing category, assign it
                for cat in existingCategories {
                    if tasks[index].title.hasPrefix(cat) {
                        tasks[index].category = cat
                        hasChanges = true
                    }
                }
            }
        }
        
        // 4. Save if we updated anything
        if hasChanges { saveData() }
    }
    
    // MARK: colorFor
    func colorFor(category: String?, scheme: ColorScheme) -> Color {
        guard let category = category else { return .gray.opacity(0.1) } // Default
        
        var hue: Double
                
        // Check if we have a saved color/hue for this category
        if let storedValue = categoryColors[category] {
            // If it starts with #, it's an old legacy Hex code. Extract Hue from it.
            if storedValue.hasPrefix("#") {
                hue = getHue(fromHex: storedValue)
                // Optional: Update storage to just the hue for future efficiency
                categoryColors[category] = String(hue)
            } else {
                // It's a stored Hue value (Double)
                hue = Double(storedValue) ?? 0.5
            }
        } else {
            // Generate a new distinct Hue
            hue = generateDistinctHue()
            categoryColors[category] = String(hue)
            saveData()
        }
        
        // APPLY YOUR SPECIFIC THEME RULES HERE
        let saturation = (scheme == .dark) ? 0.25 : 0.4
        let brightness = (scheme == .dark) ? 0.75 : 0.9
        
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
    
    // MARK: generateDistinctHue
    private func generateDistinctHue() -> Double {
        let goldenRatio = 0.618033988749895
        let count = Double(categoryColors.count)
        var hue = (count * goldenRatio).truncatingRemainder(dividingBy: 1.0)
        
        // Simple collision avoidance
        // Get existing hues
        let existingHues = categoryColors.values.compactMap { val -> Double? in
            if val.hasPrefix("#") { return getHue(fromHex: val) }
            return Double(val)
        }
        
        var attempts = 0
        while attempts < 10 {
            // If this hue is too close (within 5%) to an existing one, shift it
            let tooClose = existingHues.contains { abs($0 - hue) < 0.05 }
            if !tooClose { break }
            hue = (hue + 0.05).truncatingRemainder(dividingBy: 1.0)
            attempts += 1
        }
        
        return hue
    }
    
    // MARK: getHue
    private func getHue(fromHex hex: String) -> Double {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        
        let r, g, b: Double
        switch hex.count {
        case 3: // RGB (12-bit)
            r = Double((int >> 8) * 17) / 255.0
            g = Double((int >> 4 & 0xF) * 17) / 255.0
            b = Double((int & 0xF) * 17) / 255.0
        case 6: // RGB (24-bit)
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        default:
            return 0.5 // Default fallback
        }
        
        let minV = min(r, g, b)
        let maxV = max(r, g, b)
        let delta = maxV - minV
        
        var hue: Double = 0
        if delta != 0 {
            if maxV == r {
                hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxV == g {
                hue = ((b - r) / delta) + 2
            } else {
                hue = ((r - g) / delta) + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return hue
    }
    func batchAssignCategory(_ category: String, taskIDs: Set<UUID>) {
        for index in tasks.indices {
            if taskIDs.contains(tasks[index].id) {
                tasks[index].category = category
            }
        }
        saveData()
    }
    
    // MARK: checkForNewCategoryPattern
    // Scan for patterns to suggest categories
    // Returns a suggested Category Name if a pattern is found with >= 3 items
    func checkForNewCategoryPattern() -> String? {
        // Get all non-categorized titles
        let candidates = tasks.filter { $0.category == nil && !$0.isCompleted }
        var prefixCounts: [String: Int] = [:]
        
        for task in candidates {
            let words = task.title.split(separator: " ")
            if words.count >= 2 {
                // Check first 2 words (e.g. "CS 307")
                let prefix = words.prefix(2).joined(separator: " ")
                prefixCounts[prefix, default: 0] += 1
            }
        }
        
        // Find any prefix with >= 3 occurrences
        if let (prefix, _) = prefixCounts.first(where: { $0.value >= 3 }) {
            return prefix
        }
        return nil
    }
    
    // MARK: applyCategory
    // Apply the category to matching tasks
    func applyCategory(_ categoryName: String) {
        for index in tasks.indices {
            if tasks[index].category == nil && tasks[index].title.hasPrefix(categoryName) {
                tasks[index].category = categoryName
            }
        }
        saveData()
    }

    // MARK: autoAssignCategory
    // Auto-assign category to NEW tasks if they match an existing group
    private func autoAssignCategory(to taskTitle: String) -> String? {
        // Get list of existing categories
        let existingCategories = Set(tasks.compactMap { $0.category })
        for cat in existingCategories {
            if taskTitle.hasPrefix(cat) {
                return cat
            }
        }
        return nil
    }
    
    // MARK: addManualCategory
    // Manually add a category pattern and apply it to existing tasks
    func addManualCategory(_ pattern: String) {
        // 1. Scan existing tasks that match this pattern
        for index in tasks.indices {
            // Only overwrite if it doesn't have a category or if the user wants to re-organize
            if tasks[index].title.localizedCaseInsensitiveContains(pattern) {
                tasks[index].category = pattern
            }
        }
        saveData()
    }
    
    // MARK: getAllCategories
    // Get list of unique categories for the Manager View
    func getAllCategories() -> [String] {
        let cats = Set(tasks.compactMap { $0.category })
        return Array(cats).sorted()
    }
    
    // MARK: renameCategory
    // Rename a category globally
    func renameCategory(from oldName: String, to newName: String) {
        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        
        if let color = categoryColors[oldName] {
            categoryColors[newName] = color
            categoryColors.removeValue(forKey: oldName)
        }
        
        
        for index in tasks.indices {
            if tasks[index].category == oldName {
                tasks[index].category = newName
            }
        }
        saveData()
    }
    
    // MARK: deleteCategory
    // Delete a category (Tasks become Uncategorized)
    func deleteCategory(_ category: String) {
        for index in tasks.indices {
            if tasks[index].category == category {
                tasks[index].category = nil
            }
        }
        categoryColors.removeValue(forKey: category)
        saveData()
    }
    
    // MARK: updateCategoryMembership
    // Handle Assigning AND Un-assigning based on the checklist
    func updateCategoryMembership(category: String, finalSelectedIDs: Set<UUID>) {
        for index in tasks.indices {
            let task = tasks[index]
            
            if finalSelectedIDs.contains(task.id) {
                // If checked, assign to category
                tasks[index].category = category
            } else if task.category == category {
                // If NOT checked, but currently HAS this category, remove it (Un-assign)
                tasks[index].category = nil
            }
            // If not checked and has a DIFFERENT category, leave it alone.
        }
        saveData()
    }
    
    // MARK: updateTask
    func updateTask(_ task: TaskItem, newTitle: String, newDate: Date) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index].title = newTitle
            tasks[index].deadline = newDate
            scheduleNotification(for: tasks[index])
            saveData()
        }
    }

    // MARK: deleteTasks
    func deleteTask(id: UUID) {
        // Cancel notification before deleting
        if let task = tasks.first(where: { $0.id == id }) {
            cancelNotification(for: task)
        }
        tasks.removeAll { $0.id == id }
        saveData()
    }
    
    // MARK: deleteAllTasks
    func deleteAllTasks() {
        // 1. Cancel all future scheduled reminders
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        // 2. Remove any notifications currently sitting on the lock screen
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        
        tasks.removeAll()
        categoryColors.removeAll()
        saveData()
    }
    
    // MARK: toggleCompletion
    func toggleCompletion(for taskID: UUID) {
        if let index = tasks.firstIndex(where: { $0.id == taskID }) {
            tasks[index].isCompleted.toggle()
            if tasks[index].isCompleted {
                tasks[index].completedDate = Date()
                cancelNotification(for: tasks[index]) // Cancel if done
                handleRecurrence(for: index)
            } else {
                tasks[index].completedDate = nil
                scheduleNotification(for: tasks[index]) // Re-schedule if undone
            }
            saveData()
        }
    }
        
    // MARK: - RECURRENCE ENGINE
    // MARK: handleRecurrence
    func handleRecurrence(for index: Int) {
        guard let rule = tasks[index].recurrenceRule, !tasks[index].hasGeneratedNext else { return }
        
        var attempts = 0
        let maxAttempts = 52
        
        if let nextDate = calculateNextDate(from: tasks[index].deadline, rule: rule) {
            tasks[index].hasGeneratedNext = true
            
            var validNextDate = nextDate
            while validNextDate < Date() {
                attempts += 1
                if attempts > maxAttempts { break } // EMERGENCY BRAKE
                
                if let pushedDate = calculateNextDate(from: validNextDate, rule: rule) {
                    // Prevent infinite loop if date doesn't move forward
                    if pushedDate <= validNextDate { break }
                    validNextDate = pushedDate
                } else {
                    break
                }
            }
            
            let newTask = TaskItem(title: tasks[index].title, deadline: validNextDate, recurrenceRule: rule)
            tasks.append(newTask)
            scheduleNotification(for: newTask)
            
            pruneHistory(for: tasks[index].title)
            saveData()
        }
    }
    
    // MARK: pruneHistory
    // Deletes oldest completed copies of a task if they exceed the limit
    private func pruneHistory(for title: String) {
        let historyLimit = 52
        
        // Find all COMPLETED tasks with this specific title and recurrence
        // We sort by completion date (Oldest first)
        let matchingTasks = tasks.filter {
            $0.title == title && $0.isCompleted && $0.recurrenceRule != nil
        }.sorted {
            ($0.completedDate ?? Date.distantPast) < ($1.completedDate ?? Date.distantPast)
        }
        
        // If we have too many, identify how many to delete
        if matchingTasks.count > historyLimit {
            let deleteCount = matchingTasks.count - historyLimit
            let tasksToDelete = Set(matchingTasks.prefix(deleteCount).map { $0.id })
            
            // Cancel notifications for deleted history (just in case)
            for task in matchingTasks.prefix(deleteCount) {
                cancelNotification(for: task)
            }

            // Remove them from the main array
            tasks.removeAll { tasksToDelete.contains($0.id) }
            
            print("Memory Cleanup: Deleted \(deleteCount) old instances of '\(title)'")
        }
    }
    private func calculateNextDate(from current: Date, rule: String) -> Date? {
        let cal = Calendar.current
        
        if rule.hasPrefix("days:") {
            let components = rule.dropFirst(5).split(separator: ",").compactMap { Int($0) }
            let currentWeekday = cal.component(.weekday, from: current)
            
            for i in 1...7 {
                let nextDayIndex = (currentWeekday + i)
                let normalizedIndex = nextDayIndex > 7 ? nextDayIndex - 7 : nextDayIndex
                if components.contains(normalizedIndex) {
                    return cal.date(byAdding: .day, value: i, to: current)
                }
            }
            return nil
        }
        
        switch rule {
        case "daily": return cal.date(byAdding: .day, value: 1, to: current)
        case "weekly": return cal.date(byAdding: .weekOfYear, value: 1, to: current)
        case "monthly": return cal.date(byAdding: .month, value: 1, to: current)
        case "weekend":
            let weekday = cal.component(.weekday, from: current)
            let daysToAdd = (weekday == 7) ? 7 : (7 - weekday + 7) % 7
            let nextSat = cal.date(byAdding: .day, value: daysToAdd == 0 ? 7 : daysToAdd, to: current)
            return nextSat
        case "weekdays":
            let weekday = cal.component(.weekday, from: current)
            let add = (weekday >= 6) ? (8 - weekday) + 1 : 1
            return cal.date(byAdding: .day, value: add, to: current)
        default: return nil
        }
    }

    // MARK: - Input Pipelinen
    func addTask(from input: String) {
        let processedInput = safeNumberConvert(input)
        var taskTitle = processedInput
        var parsedDate: Date? = nil
        var recurrence: String? = nil
        var originalRecurrenceInput: String? = nil
        
        // 1. Detect Recurrence
        let recResult = detectRecurrence(taskTitle)
        if let rule = recResult.rule {
            recurrence = rule
            originalRecurrenceInput = taskTitle
            taskTitle = recResult.cleanTitle
        }
        
        // 2. Explicit Time Regex
        let explicitTimeResult = detectExplicitTime(taskTitle, baseDate: Date())
        var explicitTimeComponents: DateComponents? = nil
        if explicitTimeResult.found {
            explicitTimeComponents = explicitTimeResult.components
            taskTitle = explicitTimeResult.cleanTitle
        }
        
        // 3. Slash Date
        let slashResult = detectSlashDate(taskTitle)
        if slashResult.found {
            parsedDate = slashResult.date
            taskTitle = slashResult.cleanTitle
        }
        
        // 4. Time Keywords
        if explicitTimeComponents == nil {
            let keywordResult = detectTimeKeywords(taskTitle, baseDate: parsedDate ?? Date())
            if keywordResult.found {
                parsedDate = keywordResult.date
                taskTitle = keywordResult.cleanTitle
            }
        }
        
        // 5. Fuzzy Duration
        if parsedDate == nil && explicitTimeComponents == nil {
            let fuzzy = detectDuration(taskTitle)
            if fuzzy.found {
                parsedDate = fuzzy.date
                taskTitle = fuzzy.cleanTitle
            }
        }
        
        // 6. Manual Text Date
        if parsedDate == nil {
            let manual = detectManualDate(in: taskTitle)
            if manual.found {
                parsedDate = manual.date
                taskTitle = manual.cleanTitle
            }
        }
        
        // 7. Apple Detector
        if parsedDate == nil {
            if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
                let matches = detector.matches(in: taskTitle, options: [], range: NSRange(location: 0, length: taskTitle.utf16.count))
                if let match = matches.first, let date = match.date {
                    parsedDate = date
                    if let range = Range(match.range, in: taskTitle) {
                        let matchedString = String(taskTitle[range])
                        if matchedString.count > 1 {
                            taskTitle = taskTitle.replacingOccurrences(of: matchedString, with: "")
                        }
                    }
                }
            }
        }
        
        // Merge Logic
        if let rule = recurrence {
            if parsedDate == nil {
                parsedDate = calculateFirstOccurrence(rule: rule)
            }
            if let timeComps = explicitTimeComponents, let base = parsedDate {
                var finalComps = Calendar.current.dateComponents([.year, .month, .day], from: base)
                finalComps.hour = timeComps.hour
                finalComps.minute = timeComps.minute
                parsedDate = Calendar.current.date(from: finalComps)
            }
        } else if let timeComps = explicitTimeComponents {
            var finalComps = Calendar.current.dateComponents([.year, .month, .day], from: parsedDate ?? Date())
            finalComps.hour = timeComps.hour
            finalComps.minute = timeComps.minute
            parsedDate = Calendar.current.date(from: finalComps)
        }
        
        taskTitle = finalCleanup(taskTitle)
        let assignedCategory = autoAssignCategory(to: taskTitle)
        
        if taskTitle.trimmingCharacters(in: .whitespaces).isEmpty {
            taskTitle = "Untitled Task"
        }
        
        var finalDate = parsedDate ?? Date().addingTimeInterval(3600)
        
        if let rule = recurrence, finalDate < Date() {
            var attempts = 0
            while finalDate < Date() {
                attempts += 1
                if attempts > 52 { break }
                if let forwardedDate = calculateNextDate(from: finalDate, rule: rule) {
                    if forwardedDate <= finalDate { break }
                    finalDate = forwardedDate
                } else { break }
            }
        }
        
        // CREATE
        let newTask = TaskItem(title: taskTitle, deadline: finalDate, recurrenceRule: recurrence, category: assignedCategory)
        tasks.append(newTask)
        
        // SCHEDULE
        scheduleNotification(for: newTask)
    }
    
    // --- PARSERS ---
    
    private func calculateFirstOccurrence(rule: String) -> Date? {
        let cal = Calendar.current
        let today = Date()
        
        if rule.hasPrefix("days:") {
            let targets = rule.dropFirst(5).split(separator: ",").compactMap { Int($0) }
            let currentWeekday = cal.component(.weekday, from: today)
            
            for i in 0...7 {
                let check = (currentWeekday + i)
                let norm = check > 7 ? check - 7 : check
                if targets.contains(norm) {
                    // Default to end of day if no time specified, to ensure it doesn't expire immediately if it's today
                    if i == 0 {
                        var comps = cal.dateComponents([.year, .month, .day], from: today)
                        comps.hour = 23; comps.minute = 59
                        return cal.date(from: comps)
                    }
                    return cal.date(byAdding: .day, value: i, to: today)
                }
            }
        }
        return nil
    }
    
    // FIXED: Added detection for "5pm", "17:30", "5:00 pm"
    private func detectExplicitTime(_ text: String, baseDate: Date) -> (components: DateComponents?, cleanTitle: String, found: Bool) {
        var clean = text
        // Regex for 12hr (5pm, 5:30pm) and 24hr (17:00)
        let pattern = #"\b((1[0-2]|0?[1-9])(?::([0-5][0-9]))?\s*([ap]m)|([01]?[0-9]|2[0-3]):([0-5][0-9]))\b"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return (nil, text, false) }
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        if let match = matches.first {
            var comps = DateComponents()
            let fullMatch = nsString.substring(with: match.range).lowercased()
            
            if fullMatch.contains("am") || fullMatch.contains("pm") {
                // 12-hour format
                // Extract digits. regex group 2 is hour, 3 is min
                if let hRange = Range(match.range(at: 2), in: text),
                   let hour = Int(text[hRange]) {
                    var h = hour
                    let isPM = fullMatch.contains("pm")
                    if isPM && h != 12 { h += 12 }
                    if !isPM && h == 12 { h = 0 }
                    comps.hour = h
                    
                    if match.range(at: 3).location != NSNotFound,
                       let mRange = Range(match.range(at: 3), in: text),
                       let min = Int(text[mRange]) {
                        comps.minute = min
                    } else {
                        comps.minute = 0
                    }
                }
            } else {
                // 24-hour format
                // Group 5 is hour, 6 is min
                if let hRange = Range(match.range(at: 5), in: text),
                   let mRange = Range(match.range(at: 6), in: text),
                   let h = Int(text[hRange]),
                   let m = Int(text[mRange]) {
                    comps.hour = h
                    comps.minute = m
                }
            }
            
            clean = nsString.replacingCharacters(in: match.range, with: "")
            return (comps, clean, true)
        }
        return (nil, text, false)
    }
    
    private func detectRecurrence(_ text: String) -> (rule: String?, cleanTitle: String) {
        var clean = text
        var rule: String? = nil
        let lower = text.lowercased()
        
        if lower.contains("every") {
            let dayMap: [String: Int] = [
                "sunday": 1, "sun": 1, "monday": 2, "mon": 2, "tuesday": 3, "tue": 3,
                "wednesday": 4, "wed": 4, "thursday": 5, "thu": 5, "friday": 6, "fri": 6,
                "saturday": 7, "sat": 7
            ]
            
            var foundDays: Set<Int> = []
            var foundWords: [String] = []
            
            for (dayName, dayInt) in dayMap {
                if lower.contains(dayName) {
                    foundDays.insert(dayInt)
                    foundWords.append(dayName)
                }
            }
            
            if !foundDays.isEmpty {
                foundWords.sort { $0.count > $1.count }
                clean = clean.replacingOccurrences(of: "every", with: "", options: .caseInsensitive)
                for word in foundWords {
                    clean = clean.replacingOccurrences(of: word, with: "", options: .caseInsensitive)
                }
                let sortedDays = foundDays.sorted().map { String($0) }.joined(separator: ",")
                rule = "days:\(sortedDays)"
                return (rule, clean)
            }
            
            if lower.contains("day") {
                rule = "daily"
                clean = clean.replacingOccurrences(of: "every day", with: "", options: .caseInsensitive)
                clean = clean.replacingOccurrences(of: "everyday", with: "", options: .caseInsensitive)
            } else if lower.contains("week") {
                rule = "weekly"
                clean = clean.replacingOccurrences(of: "every week", with: "", options: .caseInsensitive)
            } else if lower.contains("month") {
                rule = "monthly"
                clean = clean.replacingOccurrences(of: "every month", with: "", options: .caseInsensitive)
            }
        }
        
        if rule == nil {
            if lower.contains("weekend") {
                rule = "weekend"
                clean = clean.replacingOccurrences(of: "weekend", with: "", options: .caseInsensitive)
            } else if lower.contains("weekdays") || lower.contains("mtwrf") {
                rule = "weekdays"
                clean = clean.replacingOccurrences(of: "weekdays", with: "", options: .caseInsensitive)
                clean = clean.replacingOccurrences(of: "mtwrf", with: "", options: .caseInsensitive)
            }
        }
        return (rule, clean)
    }
    
    private func detectSlashDate(_ text: String) -> (date: Date?, cleanTitle: String, found: Bool) {
        let pattern = #"\b(\d{1,2})/(\d{1,2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return (nil, text, false) }
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        if let match = matches.first {
            let monthStr = nsString.substring(with: match.range(at: 1))
            let dayStr = nsString.substring(with: match.range(at: 2))
            if let m = Int(monthStr), let d = Int(dayStr) {
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                comps.month = m; comps.day = d
                if let testDate = Calendar.current.date(from: comps), testDate < Date() {
                    comps.year! += 1
                }
                let clean = nsString.replacingCharacters(in: match.range, with: "")
                return (Calendar.current.date(from: comps), clean, true)
            }
        }
        return (nil, text, false)
    }
    
    private func detectTimeKeywords(_ text: String, baseDate: Date) -> (date: Date?, cleanTitle: String, found: Bool) {
        var clean = text
        var foundTime = false
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: baseDate)
        
        for (keyword, hour) in timeKeywords {
            if let range = clean.range(of: "\\b\(keyword)\\b", options: [.regularExpression, .caseInsensitive]) {
                foundTime = true
                clean.replaceSubrange(range, with: "")
                comps.hour = hour
                comps.minute = (keyword == "tonight") ? 59 : 0
                comps.second = 0
            }
        }
        if foundTime { return (Calendar.current.date(from: comps), clean, true) }
        return (nil, text, false)
    }
    
    private func safeNumberConvert(_ text: String) -> String {
        var newText = text
        let sortedKeys = numberMapping.keys.sorted { $0.count > $1.count }
        for key in sortedKeys {
            let pattern = "\\b\(key)\\b"
            if let val = numberMapping[key] {
                newText = newText.replacingOccurrences(of: pattern, with: "\(val)", options: [.regularExpression, .caseInsensitive])
            }
        }
        return newText
    }
       
    private func detectDuration(_ text: String) -> (date: Date?, cleanTitle: String, found: Bool) {
        let numberPattern = #"(\d+(?:\.\d+)?)\s*(minutes|minute|mins|min|hours|hour|hrs|hr|days|day|weeks|week|wks|wk|months|month|mo|years|year|yrs|yr)(?:\s+and\s+(?:a\s+)?half)?"#
        let nsString = text as NSString
        var totalSeconds: TimeInterval = 0
        var foundAny = false
        var cleanTitle = text
        
        if let regex = try? NSRegularExpression(pattern: numberPattern, options: .caseInsensitive) {
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            for match in matches.reversed() {
                foundAny = true
                let valString = nsString.substring(with: match.range(at: 1))
                let unitString = nsString.substring(with: match.range(at: 2)).lowercased()
                let fullString = nsString.substring(with: match.range)
                var value = Double(valString) ?? 0.0
                if fullString.lowercased().contains("half") { value += 0.5 }
                totalSeconds += convertToSeconds(value: value, unit: unitString)
                cleanTitle = (cleanTitle as NSString).replacingCharacters(in: match.range, with: "")
            }
        }
        
        let keywordPattern = #"\b(next|this|a|an|one)\s+(minutes|minute|mins|min|hours|hour|hrs|hr|days|day|weeks|week|wks|wk|months|month|mo|years|year|yrs|yr)(?:\s+and\s+(?:a\s+)?half)?"#
        if let regex = try? NSRegularExpression(pattern: keywordPattern, options: .caseInsensitive) {
            let currentNsString = cleanTitle as NSString
            let matches = regex.matches(in: cleanTitle, options: [], range: NSRange(location: 0, length: currentNsString.length))
            for match in matches.reversed() {
                foundAny = true
                let keyword = currentNsString.substring(with: match.range(at: 1)).lowercased()
                let unitString = currentNsString.substring(with: match.range(at: 2)).lowercased()
                var value = 1.0
                if keyword == "this" { value = 0.0 }
                totalSeconds += convertToSeconds(value: value, unit: unitString)
                cleanTitle = (cleanTitle as NSString).replacingCharacters(in: match.range, with: "")
            }
        }
        
        if foundAny { return (Date().addingTimeInterval(totalSeconds), cleanTitle, true) }
        return (nil, text, false)
    }
    
    private func convertToSeconds(value: Double, unit: String) -> TimeInterval {
        switch unit {
        case "min", "mins", "minute", "minutes": return value * 60
        case "hr", "hrs", "hour", "hours": return value * 3600
        case "day", "days": return value * 86400
        case "wk", "wks", "week", "weeks": return value * 604800
        case "mo", "month", "months": return value * 2_592_000
        case "yr", "yrs", "year", "years": return value * 31_536_000
        default: return 0
        }
    }
    
    private func detectManualDate(in text: String) -> (date: Date?, cleanTitle: String, found: Bool) {
        let nsString = text as NSString
        var cleanTitle = text
        var foundDate: Date? = nil
        let yearPattern = #"\b(20\d{2})\b"#
        if let yearRegex = try? NSRegularExpression(pattern: yearPattern) {
            let matches = yearRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            if let match = matches.first {
                let yearStr = nsString.substring(with: match.range)
                if let yearInt = Int(yearStr) {
                    var components = DateComponents()
                    components.year = yearInt; components.month = 1; components.day = 1
                    foundDate = Calendar.current.date(from: components)
                    cleanTitle = nsString.replacingCharacters(in: match.range, with: "")
                }
            }
        }
        let words = text.lowercased().components(separatedBy: .whitespaces)
        for word in words {
            let cleanWord = word.trimmingCharacters(in: .punctuationCharacters)
            if let monthInt = monthMap[cleanWord] {
                var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                components.month = monthInt; components.day = 1
                let currentMonth = Calendar.current.component(.month, from: Date())
                if monthInt < currentMonth { components.year! += 1 }
                if let existing = foundDate {
                    var newComps = Calendar.current.dateComponents([.year, .month, .day], from: existing)
                    newComps.month = monthInt
                    foundDate = Calendar.current.date(from: newComps)
                } else {
                    foundDate = Calendar.current.date(from: components)
                }
                cleanTitle = cleanTitle.replacingOccurrences(of: word, with: "", options: .caseInsensitive)
            }
        }
        if let date = foundDate { return (date, cleanTitle, true) }
        return (nil, text, false)
    }
    
    private func finalCleanup(_ text: String) -> String {
        var clean = text
        clean = clean.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        clean = clean.replacingOccurrences(of: " and ", with: " ")
        var previous = ""
        while clean != previous {
            previous = clean
            clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = clean.lowercased()
            if lower.hasSuffix(" by") { clean = String(clean.dropLast(3)) }
            else if lower.hasSuffix(" in") { clean = String(clean.dropLast(3)) }
            else if lower.hasSuffix(" at") { clean = String(clean.dropLast(3)) }
            else if lower.hasSuffix(" on") { clean = String(clean.dropLast(3)) }
            else if lower.hasSuffix(" for") { clean = String(clean.dropLast(4)) }
            if lower.hasPrefix("by ") { clean = String(clean.dropFirst(3)) }
            else if lower.hasPrefix("in ") { clean = String(clean.dropFirst(3)) }
            else if lower.hasPrefix("at ") { clean = String(clean.dropFirst(3)) }
            else if lower.hasPrefix("on ") { clean = String(clean.dropFirst(3)) }
            else if lower.hasPrefix("for ") { clean = String(clean.dropFirst(4)) }
        }
        return clean
    }
    
    func getTasks(for bucket: TimeBucket) -> [TaskItem] {
        let now = Date()
        
        // 1. filer tasks
        let filteredTasks = tasks.filter { task in
            if task.isCompleted { return false }
            let diff = task.deadline.timeIntervalSince(now)
            
            guard diff > 0 else { return false }
            
            // Logic: Find the smallest bucket that fits this time difference
            for systemBucket in allBuckets {
                if diff <= systemBucket.timeLimitInSeconds {
                    return systemBucket.id == bucket.id
                }
            }
            return false
        }
        
        // sort by deadline
        return filteredTasks.sorted { $0.deadline < $1.deadline }
    }
    
    func getOverdueTasks() -> [TaskItem] {
        let now = Date()
        for i in tasks.indices {
            if !tasks[i].isCompleted && tasks[i].deadline < now && tasks[i].recurrenceRule != nil && !tasks[i].hasGeneratedNext {
                handleRecurrence(for: i)
            }
        }
        return tasks.filter { !$0.isCompleted && $0.deadline < now }
            .sorted { $0.deadline < $1.deadline }
    }
    
    func getCompletedTasks() -> [TaskItem] {
        return tasks.filter { $0.isCompleted }.sorted { ($0.completedDate ?? Date()) > ($1.completedDate ?? Date()) }
    }
}
