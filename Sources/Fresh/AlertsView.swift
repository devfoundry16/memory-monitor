import AppKit
import MemoryCore
import SwiftUI

// MARK: - Header (black frame)

/// The Alerts tab's header: the IP watch's latest result and what's coming up.
struct AlertsHeader: View {
    @Environment(NotificationStore.self) private var alerts

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            HStack(alignment: .center, spacing: Theme.Space.xl) {
                HeroFigure(eyebrow: "IP Watch", value: value, companion: companion, subtitle: alerts.checkSummary)
                Spacer()
                if alerts.vpnLooksDown, alerts.restartableService != nil {
                    VStack(alignment: .trailing, spacing: Theme.Space.sm) {
                        RestartVPNButton()
                        if let message = alerts.restartMessage {
                            Text(message).font(Theme.Typeface.captionSm).foregroundStyle(Theme.Palette.onFrameMute)
                                .lineLimit(2).frame(maxWidth: 320, alignment: .trailing)
                        }
                    }
                }
            }
            .frame(height: heroHeight)

            CardGrid {
                StatCard(title: "IP Watch", value: alerts.ipWatch.enabled ? "On" : "Off",
                         summary: "Alerts when the IP leaves \(alerts.ipWatch.expectedCountry), fails, or comes back.",
                         detail: alerts.ipWatch.sshTarget.isEmpty ? "This Mac" : alerts.ipWatch.sshTarget)
                StatCard(title: "Check Every", value: "\(alerts.ipWatch.intervalMinutes) min",
                         summary: "Only a change of country alerts, not a new IP in the same country.")
                StatCard(title: "Reminders", value: "\(alerts.reminders.filter(\.enabled).count)",
                         summary: "Reminders that are on, out of \(alerts.reminders.count) in all.")
                StatCard(title: "Next Reminder", value: next.map { $0.1.formatted(date: .omitted, time: .shortened) } ?? "—",
                         summary: "Reminders only go off while Fresh is running.",
                         detail: next.map { $0.0.title })
            }
        }
    }

    private var value: String {
        guard alerts.ipWatch.enabled || alerts.lastCheck != nil else { return "Off" }
        switch alerts.lastCheck?.result {
        case .located(_, let country): return country
        case .failed: return "Failed"
        case nil: return "—"
        }
    }

    private var companion: String? {
        if case .located(let ip, _) = alerts.lastCheck?.result { return ip }
        return nil
    }

    private var next: (Reminder, Date)? {
        alerts.reminders.compactMap { r in alerts.nextDue[r.id].map { (r, $0) } }.min { $0.1 < $1.1 }
    }
}

/// Restarts the VPN service on the SSH host; shown when the last check says the VPN is down.
private struct RestartVPNButton: View {
    @Environment(NotificationStore.self) private var alerts

    var body: some View {
        Button(alerts.restarting ? "Restarting…" : "Restart VPN") { Task { await alerts.restartVPN() } }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(alerts.restarting)
            .help("Runs sudo systemctl restart \(alerts.restartableService ?? "") on \(alerts.ipWatch.sshTarget)")
    }
}

extension NotificationStore {
    var checkSummary: String {
        if checking { return "Checking…" }
        guard let (date, result) = lastCheck else {
            return ipWatch.enabled ? "Not checked yet." : "Turn it on below to check every few minutes."
        }
        let time = date.formatted(date: .omitted, time: .shortened)
        switch result {
        case .located(let ip, let country): return "\(ip) is in \(country) · checked at \(time)"
        case .failed(let reason): return "Check failed at \(time): \(reason)"
        }
    }
}

// MARK: - Body

struct AlertsView: View {
    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: Theme.Space.xxl) {
                IPWatchSettingsView().frame(maxWidth: .infinity, alignment: .topLeading)
                Theme.Palette.hairline.frame(width: 1)
                RemindersView().frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(Theme.Space.xxl)
        }
        .background(Theme.Palette.canvas)
    }
}

private struct IPWatchSettingsView: View {
    @Environment(NotificationStore.self) private var alerts

    var body: some View {
        @Bindable var alerts = alerts
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Text("IP Watch").font(Theme.Typeface.headingMd).foregroundStyle(Theme.Palette.ink)
            Text("Checks which country an IP is in, from this Mac or from another machine over SSH, such as a VM behind a VPN.")
                .font(Theme.Typeface.captionSm).foregroundStyle(Theme.Palette.mute)
                .fixedSize(horizontal: false, vertical: true)
            CheckRow(title: "Watch the IP", symbol: "network", isOn: $alerts.ipWatch.enabled)

            Grid(alignment: .leading, horizontalSpacing: Theme.Space.md, verticalSpacing: Theme.Space.sm) {
                GridRow {
                    Eyebrow("SSH host")
                    ThemedField(text: $alerts.ipWatch.sshTarget, prompt: "user@host, or empty for this Mac")
                }
                GridRow {
                    Eyebrow("SSH key")
                    HStack(spacing: Theme.Space.sm) {
                        ThemedField(text: $alerts.ipWatch.keyPath, prompt: "Default keys")
                        Button("Choose…") { chooseKey() }.buttonStyle(OutlineButtonStyle())
                    }
                }
                GridRow {
                    Eyebrow("VPN service")
                    ThemedField(text: .init(get: { alerts.ipWatch.vpnService ?? "" }, set: { alerts.ipWatch.vpnService = $0 }),
                                prompt: "systemd unit for Restart VPN, e.g. wg-quick@us-sea")
                }
                GridRow {
                    Eyebrow("Country")
                    ThemedField(text: $alerts.ipWatch.expectedCountry, prompt: "US").frame(width: 80)
                }
                GridRow {
                    Eyebrow("Every")
                    Stepper(value: $alerts.ipWatch.intervalMinutes, in: 1...120) {
                        Text("\(alerts.ipWatch.intervalMinutes) min").font(Theme.Typeface.body).foregroundStyle(Theme.Palette.ink)
                    }
                    .fixedSize()
                }
                GridRow {
                    Eyebrow("Title")
                    ThemedField(text: $alerts.ipWatch.title, prompt: "IP Watch")
                }
            }

            HStack(spacing: Theme.Space.md) {
                Button("Check Now") { Task { await alerts.checkNow() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(alerts.checking)
                Text(alerts.checkSummary)
                    .font(Theme.Typeface.captionSm).foregroundStyle(Theme.Palette.mute)
                    .lineLimit(2)
            }

            if alerts.notificationsDenied {
                Text("Notifications are off for Fresh in System Settings ▸ Notifications. Sounds still play.")
                    .font(Theme.Typeface.captionSm).foregroundStyle(Theme.Palette.warning)
            }

            Theme.Palette.hairline.frame(height: 1)

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Messages").font(Theme.Typeface.bodyStrong).foregroundStyle(Theme.Palette.ink)
                Text("{ip}, {country} and {expected} are filled in.")
                    .font(Theme.Typeface.captionSm).foregroundStyle(Theme.Palette.mute)
            }
            MessageEditor(title: "Not in the expected country", message: $alerts.ipWatch.notExpected) { alerts.testAlert(.notExpected) }
            MessageEditor(title: "Check failed", message: $alerts.ipWatch.failed) { alerts.testAlert(.failed) }
            MessageEditor(title: "Back in the expected country", message: $alerts.ipWatch.recovered) { alerts.testAlert(.recovered) }
        }
    }

    private func chooseKey() {
        let panel = NSOpenPanel()
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        panel.showsHiddenFiles = true
        panel.canChooseDirectories = false
        panel.message = "Choose the SSH private key"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        alerts.ipWatch.keyPath = url.path.hasPrefix(home + "/") ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

private struct MessageEditor: View {
    let title: String
    @Binding var message: AlertMessage
    let test: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Eyebrow(title)
            ThemedField(text: $message.text, prompt: "Message")
            HStack(spacing: Theme.Space.md) {
                SoundPicker(sound: $message.sound)
                Spacer()
                Button("Test Alert", action: test).buttonStyle(OutlineButtonStyle())
            }
        }
    }
}

// MARK: - Reminders

private struct RemindersView: View {
    @Environment(NotificationStore.self) private var alerts
    /// Plain `State` rather than `@State`, whose macro needs Xcode.
    private let editingState = State<Reminder?>(initialValue: nil)
    private let deletingState = State<Reminder?>(initialValue: nil)
    private var editing: Reminder? {
        get { editingState.wrappedValue }
        nonmutating set { editingState.wrappedValue = newValue }
    }
    private var deleting: Reminder? {
        get { deletingState.wrappedValue }
        nonmutating set { deletingState.wrappedValue = newValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            HStack {
                Text("Reminders").font(Theme.Typeface.headingMd).foregroundStyle(Theme.Palette.ink)
                Spacer()
                Button("Add Reminder") {
                    editing = Reminder(title: "", schedule: .daily(hour: 9, minute: 0))
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            Text("Your own alarms: once, daily, on chosen weekdays, or every few minutes, each with its own text and sound.")
                .font(Theme.Typeface.captionSm).foregroundStyle(Theme.Palette.mute)
                .fixedSize(horizontal: false, vertical: true)

            if alerts.reminders.isEmpty {
                Text("No reminders yet.")
                    .font(Theme.Typeface.body).foregroundStyle(Theme.Palette.mute)
                    .padding(.vertical, Theme.Space.lg)
            }
            ForEach(alerts.reminders) { reminder in
                row(reminder)
                Theme.Palette.hairline.frame(height: 1)
            }
        }
        .sheet(item: editingState.projectedValue) { reminder in
            ReminderEditor(reminder: reminder)
        }
        .confirmationDialog("Delete “\(deleting?.title ?? "")”?", isPresented: .init(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) { deleting.map(alerts.delete) }
        }
    }

    private func row(_ reminder: Reminder) -> some View {
        HStack(spacing: Theme.Space.md) {
            Button { alerts.setEnabled(reminder.id, !reminder.enabled) } label: {
                CheckBox(isOn: reminder.enabled)
            }
            .buttonStyle(.plain)
            .help(reminder.enabled ? "Turn off" : "Turn on")

            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title.isEmpty ? "Untitled" : reminder.title)
                    .font(Theme.Typeface.bodyStrong).foregroundStyle(Theme.Palette.ink)
                Text(reminder.schedule.summary + " · " + status(reminder))
                    .font(Theme.Typeface.captionSm).foregroundStyle(Theme.Palette.mute)
            }
            Spacer()
            Button("Edit") { editing = reminder }.buttonStyle(OutlineButtonStyle())
            Button { deleting = reminder } label: {
                Image(systemName: "trash").foregroundStyle(Theme.Palette.mute).frame(width: 24, height: 28).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Delete")
        }
        .frame(minHeight: 44)
    }

    private func status(_ reminder: Reminder) -> String {
        if let due = alerts.nextDue[reminder.id] {
            return "next " + due.formatted(Calendar.current.isDateInToday(due) ? .dateTime.hour().minute() : .dateTime.weekday().month().day().hour().minute())
        }
        if case .once = reminder.schedule, reminder.schedule.nextFire(after: .now) == nil { return "done" }
        return reminder.enabled ? "won't go off" : "off"
    }
}

private struct ReminderEditor: View {
    @Environment(NotificationStore.self) private var alerts
    @Environment(\.dismiss) private var dismiss

    enum Kind: Hashable { case once, daily, weekdays, every }

    struct Draft {
        var reminder: Reminder
        var kind: Kind
        var date: Date
        var time: Date
        var days: Set<Int>
        var minutes: Int
    }
    /// Plain `State` rather than `@State`, whose macro needs Xcode.
    private let state: State<Draft>
    private var draft: Binding<Draft> { state.projectedValue }
    private var d: Draft { state.wrappedValue }

    /// Monday first.
    private static let weekOrder = [2, 3, 4, 5, 6, 7, 1]

    init(reminder: Reminder) {
        let calendar = Calendar.current
        func at(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
        }
        var kind = Kind.daily, date = Date.now.addingTimeInterval(3600), time = at(9, 0)
        var days: Set<Int> = [2, 3, 4, 5, 6], minutes = 30
        switch reminder.schedule {
        case .once(let d): (kind, date) = (.once, d)
        case .daily(let h, let m): (kind, time) = (.daily, at(h, m))
        case .weekdays(let ds, let h, let m): (kind, days, time) = (.weekdays, ds, at(h, m))
        case .every(let mins, let start): (kind, minutes, date) = (.every, mins, start)
        }
        state = State(initialValue: Draft(reminder: reminder, kind: kind, date: date, time: time, days: days, minutes: minutes))
    }

    private var schedule: ReminderSchedule {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: d.time)
        let (hour, minute) = (parts.hour ?? 0, parts.minute ?? 0)
        return switch d.kind {
        case .once: .once(d.date)
        case .daily: .daily(hour: hour, minute: minute)
        case .weekdays: .weekdays(days: d.days, hour: hour, minute: minute)
        case .every: .every(minutes: d.minutes, from: d.date)
        }
    }

    private var current: Reminder {
        var r = d.reminder
        r.schedule = schedule
        return r
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            HStack(spacing: Theme.Space.sm) {
                CornerSquare()
                Eyebrow("Reminder")
            }
            Grid(alignment: .leading, horizontalSpacing: Theme.Space.md, verticalSpacing: Theme.Space.md) {
                GridRow {
                    Eyebrow("Title")
                    ThemedField(text: draft.reminder.title, prompt: "Stand up and stretch")
                }
                GridRow {
                    Eyebrow("Text")
                    ThemedField(text: draft.reminder.body, prompt: "Optional")
                }
                GridRow {
                    Eyebrow("Repeat")
                    PillTabs(options: [(Kind.once, "Once"), (.daily, "Daily"), (.weekdays, "Weekdays"), (.every, "Every")],
                             selection: draft.kind)
                }
                GridRow {
                    Eyebrow(d.kind == .every ? "Starting" : d.kind == .once ? "At" : "Time")
                    timing
                }
                GridRow {
                    Eyebrow("Sound")
                    SoundPicker(sound: draft.reminder.sound)
                }
            }

            Text(current.schedule.nextFire(after: .now).map {
                "Next: " + $0.formatted(date: .abbreviated, time: .shortened)
            } ?? "This reminder won't go off: pick a time in the future or at least one day.")
                .font(Theme.Typeface.captionSm)
                .foregroundStyle(current.schedule.nextFire(after: .now) == nil ? Theme.Palette.warning : Theme.Palette.mute)

            HStack(spacing: Theme.Space.md) {
                Button("Test") { alerts.test(current) }.buttonStyle(OutlineButtonStyle())
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(OutlineButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    var r = current
                    if r.title.trimmingCharacters(in: .whitespaces).isEmpty { r.title = "Reminder" }
                    r.enabled = true
                    alerts.update(r)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 520)
        .background(Theme.Palette.canvas)
        .environment(\.colorScheme, Theme.bodyScheme)
    }

    @ViewBuilder private var timing: some View {
        switch d.kind {
        case .once:
            DatePicker("", selection: draft.date, in: Date.now..., displayedComponents: [.date, .hourAndMinute]).labelsHidden()
        case .daily:
            DatePicker("", selection: draft.time, displayedComponents: .hourAndMinute).labelsHidden()
        case .weekdays:
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.xs) {
                    ForEach(Self.weekOrder, id: \.self) { day in
                        let on = d.days.contains(day)
                        Button { if on { draft.wrappedValue.days.remove(day) } else { draft.wrappedValue.days.insert(day) } } label: {
                            Text(Calendar.current.shortWeekdaySymbols[day - 1])
                                .font(Theme.Typeface.captionMd)
                                .foregroundStyle(on ? Theme.Palette.onSelection : Theme.Palette.ink)
                                .frame(width: 40, height: 28)
                                .background(on ? Theme.Palette.selection : .clear, in: .rect(cornerRadius: Theme.buttonRadius))
                                .overlay(RoundedRectangle(cornerRadius: Theme.buttonRadius)
                                    .strokeBorder(on ? .clear : Theme.Palette.hairline, lineWidth: 1))
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                DatePicker("", selection: draft.time, displayedComponents: .hourAndMinute).labelsHidden()
            }
        case .every:
            HStack(spacing: Theme.Space.md) {
                DatePicker("", selection: draft.date, displayedComponents: [.date, .hourAndMinute]).labelsHidden()
                Stepper(value: draft.minutes, in: 1...1440) {
                    Text("every \(d.minutes) min").font(Theme.Typeface.body).foregroundStyle(Theme.Palette.ink)
                }
                .fixedSize()
            }
        }
    }
}

extension ReminderSchedule {
    var summary: String {
        func clock(_ hour: Int, _ minute: Int) -> String {
            let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
            return date.formatted(date: .omitted, time: .shortened)
        }
        switch self {
        case .once(let date):
            return "Once, " + date.formatted(date: .abbreviated, time: .shortened)
        case .daily(let hour, let minute):
            return "Daily at " + clock(hour, minute)
        case .weekdays(let days, let hour, let minute):
            let names = [2, 3, 4, 5, 6, 7, 1].filter(days.contains).map { Calendar.current.shortWeekdaySymbols[$0 - 1] }
            return (names.isEmpty ? "No days" : names.joined(separator: ", ")) + " at " + clock(hour, minute)
        case .every(let minutes, _):
            return minutes % 60 == 0 ? "Every \(minutes / 60) h" : "Every \(minutes) min"
        }
    }
}

// MARK: - Shared controls

/// A system sound menu, how many times it plays, and a preview button.
private struct SoundPicker: View {
    @Environment(NotificationStore.self) private var alerts
    @Binding var sound: AlertSound

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Menu {
                ForEach(alerts.soundNames, id: \.self) { name in
                    Button(name) { sound.name = name; alerts.play(AlertSound(name: name)) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2")
                    Text(sound.name)
                }
                .font(Theme.Typeface.body)
            }
            .menuStyle(.button)
            .fixedSize()
            Stepper(value: $sound.repeats, in: 1...10) {
                Text("× \(sound.repeats)").font(Theme.Typeface.body).foregroundStyle(Theme.Palette.ink).monospacedDigit()
            }
            .fixedSize()
            Button { alerts.play(sound) } label: {
                Image(systemName: "play.fill").foregroundStyle(Theme.Palette.primary).frame(width: 24, height: 24).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Play")
        }
    }
}

/// A text field drawn like the search field: hairline border, accent when focused.
private struct ThemedField: View {
    @Binding var text: String
    let prompt: String
    @FocusState private var focused: Bool

    var body: some View {
        TextField(prompt, text: $text)
            .textFieldStyle(.plain)
            .font(Theme.Typeface.body)
            .foregroundStyle(Theme.Palette.ink)
            .focused($focused)
            .padding(.horizontal, Theme.Space.md)
            .frame(height: 30)
            .background(Theme.Palette.canvas, in: .rect(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius)
                .strokeBorder(focused ? Theme.Palette.primary : Theme.Palette.hairline, lineWidth: focused ? 2 : 1))
    }
}
