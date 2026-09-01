//
//  ReminderEditor.swift
//  Haptic Alert Watch
//
//  Create and edit reminders (SPEC §10 step 6).
//
//  Edits are made against a draft and applied on Save, so a half-configured
//  schedule never reaches the store — reconciliation runs on every change,
//  and scheduling an alarm from a partially edited rule would fire at a time
//  the user never asked for.
//

import SwiftUI
import SwiftData

/// The three schedule shapes, as a flat choice for the picker.
enum ScheduleKind: String, CaseIterable, Identifiable {
    case relative, fixed, oneOff

    var id: String { rawValue }

    var label: String {
        switch self {
        case .relative: "After completion"
        case .fixed: "Fixed times"
        case .oneOff: "Once"
        }
    }

    var explanation: String {
        switch self {
        case .relative: "Counts from when you last marked it done. Deferring doesn't move it — only Done does."
        case .fixed: "Anchored to the clock. Completing early or late doesn't shift the next one."
        case .oneOff: "Fires once, then it's finished."
        }
    }
}

/// Mutable editing state, converted to a `ScheduleType` only on save.
struct ReminderDraft {
    var title: String = ""
    var kind: ScheduleKind = .relative
    var isEnabled: Bool = true
    var categoryID: UUID?

    // relative
    var intervalHours: Int = 3
    var intervalMinutes: Int = 0
    var usesAnchorReset: Bool = false
    var anchorResetTime: Date = Calendar.current.date(
        from: DateComponents(hour: 7, minute: 0)
    ) ?? .now

    // fixed
    var times: [Date] = [
        Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? .now
    ]
    var weekdays: Set<Int> = []

    // one-off
    var oneOffDate: Date = .now.addingTimeInterval(3600)

    var intervalSeconds: TimeInterval {
        TimeInterval(intervalHours * 3600 + intervalMinutes * 60)
    }

    /// A relative reminder with a zero interval would fire continuously.
    var isValid: Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch kind {
        case .relative: return intervalSeconds >= 60
        case .fixed: return !times.isEmpty
        case .oneOff: return true
        }
    }

    init() {}

    init(from reminder: Reminder) {
        title = reminder.title
        isEnabled = reminder.isEnabled
        categoryID = reminder.categoryID

        let calendar = Calendar.current
        switch reminder.schedule {
        case let .relativeToCompletion(interval, reset):
            kind = .relative
            intervalHours = Int(interval) / 3600
            intervalMinutes = (Int(interval) % 3600) / 60
            if let reset, let date = calendar.date(from: reset) {
                usesAnchorReset = true
                anchorResetTime = date
            }
        case let .fixed(componentTimes, days):
            kind = .fixed
            times = componentTimes.compactMap { calendar.date(from: $0) }
            weekdays = days
        case let .oneOff(date):
            kind = .oneOff
            oneOffDate = date
        }
    }

    func makeSchedule(calendar: Calendar = .current) -> ScheduleType {
        switch kind {
        case .relative:
            let reset = usesAnchorReset
                ? calendar.dateComponents([.hour, .minute], from: anchorResetTime)
                : nil
            return .relativeToCompletion(interval: intervalSeconds, anchorReset: reset)
        case .fixed:
            let components = times.map { calendar.dateComponents([.hour, .minute], from: $0) }
            return .fixed(times: components, weekdays: weekdays)
        case .oneOff:
            return .oneOff(date: oneOffDate)
        }
    }
}

struct ReminderEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \AlertCategory.name) private var categories: [AlertCategory]

    /// nil when creating.
    let existing: Reminder?
    @State private var draft: ReminderDraft
    @State private var showingDeleteConfirmation = false

    init(existing: Reminder? = nil) {
        self.existing = existing
        _draft = State(initialValue: existing.map(ReminderDraft.init) ?? ReminderDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $draft.title)
                    Toggle("Enabled", isOn: $draft.isEnabled)
                }

                Section("Schedule") {
                    Picker("Type", selection: $draft.kind) {
                        ForEach(ScheduleKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Text(draft.kind.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                switch draft.kind {
                case .relative: relativeSection
                case .fixed: fixedSection
                case .oneOff: oneOffSection
                }

                categorySection

                if existing != nil {
                    Section {
                        Button("Delete Reminder", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Reminder" : "Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!draft.isValid)
                }
            }
            .confirmationDialog(
                "Delete this reminder and its history?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { delete() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Schedule sections

    private var relativeSection: some View {
        Section("Interval") {
            HStack {
                Picker("Hours", selection: $draft.intervalHours) {
                    ForEach(0..<24) { Text("\($0)h").tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)

                Picker("Minutes", selection: $draft.intervalMinutes) {
                    ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) {
                        Text("\($0)m").tag($0)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 120)

            Toggle("Reset daily", isOn: $draft.usesAnchorReset)
            if draft.usesAnchorReset {
                DatePicker(
                    "Reset at",
                    selection: $draft.anchorResetTime,
                    displayedComponents: .hourAndMinute
                )
                // SPEC §5.3: without this, a relative schedule walks later
                // every day as completions drift.
                Text("Re-bases the schedule each morning so it can't drift later and later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fixedSection: some View {
        Group {
            Section("Times") {
                ForEach(draft.times.indices, id: \.self) { index in
                    DatePicker(
                        "Time \(index + 1)",
                        selection: $draft.times[index],
                        displayedComponents: .hourAndMinute
                    )
                }
                .onDelete { draft.times.remove(atOffsets: $0) }

                Button("Add time") {
                    draft.times.append(draft.times.last ?? .now)
                }
            }

            Section("Days") {
                WeekdaySelector(selection: $draft.weekdays)
                Text(draft.weekdays.isEmpty ? "Every day" : "Selected days only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var oneOffSection: some View {
        Section("When") {
            DatePicker("Date", selection: $draft.oneOffDate, in: Date()...)
        }
    }

    private var categorySection: some View {
        Section("Category") {
            if categories.isEmpty {
                Text("A default category will be created.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Category", selection: $draft.categoryID) {
                    ForEach(categories) { category in
                        Label(category.name, systemImage: category.symbolName)
                            .tag(Optional(category.id))
                    }
                }
            }
            // §7.1: alert identity is assigned, never chosen. Say so plainly
            // rather than leaving a picker-shaped hole users go looking for.
            Text("Alert sound is assigned automatically. Apple Watch always uses its standard alarm alert.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func save() {
        let categoryID = draft.categoryID ?? defaultCategoryID()
        let schedule = draft.makeSchedule()

        if let existing {
            existing.title = draft.title.trimmingCharacters(in: .whitespaces)
            existing.schedule = schedule
            existing.isEnabled = draft.isEnabled
            existing.categoryID = categoryID
        } else {
            context.insert(Reminder(
                title: draft.title.trimmingCharacters(in: .whitespaces),
                categoryID: categoryID,
                schedule: schedule,
                isEnabled: draft.isEnabled
            ))
        }
        try? context.save()
        reconcile()
        dismiss()
    }

    private func delete() {
        if let existing { context.delete(existing) }
        try? context.save()
        reconcile()
        dismiss()
    }

    private func defaultCategoryID() -> UUID {
        if let first = categories.first { return first.id }
        let category = AlertCategory(
            name: "Reminders",
            symbolName: "bell.fill",
            colorHex: "#007AFF",
            existingCount: 0
        )
        context.insert(category)
        return category.id
    }

    /// SPEC §6: reconcile on any reminder create/update/delete.
    private func reconcile() {
        let context = self.context
        Task { await ReconciliationService(context: context).reconcile() }
    }
}

/// Weekday chips. Empty selection means every day.
struct WeekdaySelector: View {
    @Binding var selection: Set<Int>

    private var symbols: [(index: Int, label: String)] {
        let calendar = Calendar.current
        // Calendar weekdays are 1-based starting Sunday; respect the user's
        // first-day-of-week rather than assuming Sunday.
        return (0..<7).map { offset in
            let weekday = (calendar.firstWeekday - 1 + offset) % 7 + 1
            return (weekday, String(calendar.veryShortWeekdaySymbols[weekday - 1]))
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(symbols, id: \.index) { day in
                let isOn = selection.contains(day.index)
                Button {
                    if isOn { selection.remove(day.index) } else { selection.insert(day.index) }
                } label: {
                    Text(day.label)
                        .font(.caption)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(isOn ? Color.accentColor : Color.secondary.opacity(0.15))
                        .foregroundStyle(isOn ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
