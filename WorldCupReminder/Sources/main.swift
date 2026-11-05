import SwiftUI
import UserNotifications

// MARK: - Models

struct Probabilities: Codable {
    let home_win: Double
    let draw: Double
    let away_win: Double
}

struct Prediction: Codable {
    let predicted_outcome: String
    let probabilities: Probabilities
    let confidence: String
    let rationale: String
}

struct Match: Codable, Identifiable {
    let match_id: Int
    let group: String
    let date: String
    let kickoff_pst: String
    let venue: String
    let city: String
    let home: String
    let away: String
    let prediction: Prediction
    let status: String
    let result: String?

    var id: Int { match_id }

    var kickoff: Date? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.timeZone = TimeZone(identifier: "America/Los_Angeles")
        return fmt.date(from: "\(date) \(kickoff_pst)")
    }

    func involves(_ teams: Set<String>) -> Bool {
        teams.contains(home) || teams.contains(away)
    }
}

struct TeamInfo: Codable, Identifiable {
    let team: String
    let group: String
    let fifa_rank: Int
    var id: String { team }
}

struct Dataset: Codable {
    let matches: [Match]
    let teams: [TeamInfo]
}

// MARK: - Store

final class Store: ObservableObject {
    static let shared = Store()

    let matches: [Match]
    let teams: [TeamInfo]

    @Published var selectedTeams: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(selectedTeams), forKey: "selectedTeams")
            rescheduleNotifications()
        }
    }

    private init() {
        guard let url = Bundle.main.url(forResource: "matches", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dataset = try? JSONDecoder().decode(Dataset.self, from: data) else {
            matches = []
            teams = []
            selectedTeams = []
            return
        }
        matches = dataset.matches.sorted { ($0.kickoff ?? .distantFuture) < ($1.kickoff ?? .distantFuture) }
        teams = dataset.teams.sorted { $0.group == $1.group ? $0.fifa_rank < $1.fifa_rank : $0.group < $1.group }
        selectedTeams = Set(UserDefaults.standard.stringArray(forKey: "selectedTeams") ?? [])
        rescheduleNotifications()
    }

    var upcomingSelected: [Match] {
        matches.filter { $0.involves(selectedTeams) && ($0.kickoff ?? .distantPast) > Date() }
    }

    var pastSelected: [Match] {
        matches.filter { $0.involves(selectedTeams) && ($0.kickoff ?? .distantPast) <= Date() }
    }

    // MARK: Notifications

    func rescheduleNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard !selectedTeams.isEmpty else { return }

        for match in matches {
            guard match.involves(selectedTeams),
                  let kickoff = match.kickoff else { continue }
            let fireDate = kickoff.addingTimeInterval(-3600)
            guard fireDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = "⚽ Kickoff in 1 hour: \(match.home) vs \(match.away)"
            content.subtitle = "\(timeString(kickoff)) · \(match.venue), \(match.city)"
            content.body = predictionLine(for: match)
            content.sound = .default

            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(
                identifier: "match-\(match.match_id)", content: content, trigger: trigger)
            center.add(request)
        }
    }

    func predictionLine(for match: Match) -> String {
        let p = match.prediction.probabilities
        // Orient probabilities to the user's team when exactly one side is selected.
        if selectedTeams.contains(match.home) && !selectedTeams.contains(match.away) {
            return "\(match.home): win \(pct(p.home_win)) · draw \(pct(p.draw)) · lose \(pct(p.away_win))"
        }
        if selectedTeams.contains(match.away) && !selectedTeams.contains(match.home) {
            return "\(match.away): win \(pct(p.away_win)) · draw \(pct(p.draw)) · lose \(pct(p.home_win))"
        }
        return "\(match.home) \(pct(p.home_win)) · draw \(pct(p.draw)) · \(match.away) \(pct(p.away_win))"
    }

    // MARK: In-app rolling-ball reminders

    private var firedReminders: Set<Int> {
        get { Set(UserDefaults.standard.array(forKey: "firedReminders") as? [Int] ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "firedReminders") }
    }

    /// Called by a timer. Fires the goal animation for any selected-team match
    /// inside its 1-hour-before-kickoff window, then cancels the fallback banner.
    func checkDueReminders() {
        let now = Date()
        for match in matches {
            guard match.involves(selectedTeams),
                  let kickoff = match.kickoff,
                  now >= kickoff.addingTimeInterval(-3600), now < kickoff,
                  !firedReminders.contains(match.match_id) else { continue }
            firedReminders.insert(match.match_id)
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: ["match-\(match.match_id)"])
            OverlayController.shared.show(
                title: "\(match.home) vs \(match.away) — kickoff in 1 hour!",
                subtitle: "\(timeString(kickoff)) · \(match.venue), \(match.city)",
                prediction: predictionLine(for: match))
        }
    }

    func sendTestNotification() {
        if let match = upcomingSelected.first, let kickoff = match.kickoff {
            OverlayController.shared.show(
                title: "\(match.home) vs \(match.away) — kickoff in 1 hour!",
                subtitle: "\(timeString(kickoff)) · \(match.venue), \(match.city)",
                prediction: predictionLine(for: match))
        } else {
            OverlayController.shared.show(
                title: "World Cup Reminder — test",
                subtitle: "This is how match reminders will look",
                prediction: "Pick teams to get real reminders 1 hour before kickoff")
        }
    }
}

// MARK: - Rolling-ball goal overlay

final class OverlayController {
    static let shared = OverlayController()
    private var window: NSWindow?

    func show(title: String, subtitle: String, prediction: String) {
        dismiss()
        guard let screen = NSScreen.main else { return }
        let height: CGFloat = 340
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.minY,
                           width: screen.frame.width, height: height)
        let win = NSWindow(contentRect: frame, styleMask: .borderless,
                           backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.level = .statusBar
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.isReleasedWhenClosed = false
        win.contentView = NSHostingView(rootView: GoalOverlayView(
            title: title, subtitle: subtitle, prediction: prediction,
            onDismiss: { [weak self] in self?.dismiss() }))
        win.orderFrontRegardless()
        window = win
    }

    func dismiss() {
        window?.orderOut(nil)
        window = nil
    }
}

struct GoalOverlayView: View {
    let title: String
    let subtitle: String
    let prediction: String
    let onDismiss: () -> Void

    @State private var rolling = false
    @State private var scored = false

    private let rollDuration = 2.8

    @ViewBuilder
    private var goalImage: some View {
        if let url = Bundle.main.url(forResource: "goal", withExtension: "png"),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(width: 240)
        } else {
            Text("🥅").font(.system(size: 120))
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Goal at bottom center
                goalImage
                    .scaleEffect(scored ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.4), value: scored)
                    .position(x: geo.size.width / 2, y: geo.size.height - 80)

                // Ball rolls in from the right edge and settles in the net
                Text("⚽")
                    .font(.system(size: scored ? 44 : 58))
                    .rotationEffect(.degrees(rolling ? -1440 : 0))
                    .position(x: rolling ? geo.size.width / 2 : geo.size.width - 40,
                              y: geo.size.height - (scored ? 60 : 42))
                    .animation(.easeOut(duration: rollDuration), value: rolling)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: scored)

                // Match card appears once the ball is in the net
                if scored {
                    VStack(spacing: 8) {
                        Text("⚽ GOAL! \(title)")
                            .font(.custom("Marker Felt", size: 26))
                        Text(subtitle)
                            .font(.custom("Marker Felt", size: 19))
                        Text(prediction)
                            .font(.custom("Marker Felt", size: 21))
                        Text("click to dismiss")
                            .font(.custom("Marker Felt", size: 12))
                            .opacity(0.6)
                    }
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(red: 0.30, green: 0.94, blue: 0.10)))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.black, lineWidth: 3))
                    .position(x: geo.size.width / 2, y: geo.size.height - 250)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .onAppear {
            rolling = true
            DispatchQueue.main.asyncAfter(deadline: .now() + rollDuration) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { scored = true }
                NSSound(named: "Glass")?.play()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + rollDuration + 15) { onDismiss() }
        }
    }
}

func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

func timeString(_ date: Date) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "EEE MMM d, h:mm a"
    fmt.timeZone = TimeZone(identifier: "America/Los_Angeles")
    return fmt.string(from: date) + " PDT"
}

// MARK: - Views

struct ContentView: View {
    @ObservedObject var store = Store.shared
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("⚽ FIFA World Cup 2026")
                    .font(.headline)
                Spacer()
                Button("Preview Goal") { store.sendTestNotification() }
                    .controlSize(.small)
                Button("Quit") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
            .padding(10)

            Picker("", selection: $tab) {
                Text("My Teams (\(store.selectedTeams.count))").tag(0)
                Text("Matches (\(store.upcomingSelected.count))").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 10)

            if tab == 0 {
                TeamPickerView()
            } else {
                MatchListView()
            }
        }
        .frame(width: 420, height: 560)
    }
}

struct TeamPickerView: View {
    @ObservedObject var store = Store.shared
    @State private var search = ""

    var filtered: [TeamInfo] {
        search.isEmpty ? store.teams
            : store.teams.filter { $0.team.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 6) {
            TextField("Search teams…", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 10)
                .padding(.top, 8)

            Text("Pick teams to follow — you'll get a pop-up 1 hour before each of their matches.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)

            List {
                ForEach(Dictionary(grouping: filtered, by: \.group).sorted(by: { $0.key < $1.key }), id: \.key) { group, teams in
                    Section("Group \(group)") {
                        ForEach(teams) { team in
                            Toggle(isOn: Binding(
                                get: { store.selectedTeams.contains(team.team) },
                                set: { on in
                                    if on { store.selectedTeams.insert(team.team) }
                                    else { store.selectedTeams.remove(team.team) }
                                }
                            )) {
                                HStack {
                                    Text(team.team)
                                    Spacer()
                                    Text("FIFA #\(team.fifa_rank)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct MatchListView: View {
    @ObservedObject var store = Store.shared

    var body: some View {
        if store.selectedTeams.isEmpty {
            VStack {
                Spacer()
                Text("No teams selected").font(.title3)
                Text("Pick teams in the My Teams tab.")
                    .foregroundColor(.secondary)
                Spacer()
            }
        } else {
            List {
                if !store.upcomingSelected.isEmpty {
                    Section("Upcoming") {
                        ForEach(store.upcomingSelected) { MatchRow(match: $0) }
                    }
                }
                if !store.pastSelected.isEmpty {
                    Section("Played / In Progress") {
                        ForEach(store.pastSelected.reversed()) { MatchRow(match: $0) }
                    }
                }
            }
        }
    }
}

struct MatchRow: View {
    @ObservedObject var store = Store.shared
    let match: Match

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(match.home) vs \(match.away)").bold()
                Spacer()
                if let result = match.result {
                    Text(result).bold().foregroundColor(.secondary)
                } else if match.status == "in_progress" {
                    Text("LIVE").bold().foregroundColor(.red)
                }
            }
            if let kickoff = match.kickoff {
                Text("\(timeString(kickoff)) · \(match.venue), \(match.city) · Group \(match.group)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            ProbabilityBar(match: match)
            Text(store.predictionLine(for: match) + "  (confidence: \(match.prediction.confidence))")
                .font(.caption)
        }
        .padding(.vertical, 3)
    }
}

struct ProbabilityBar: View {
    let match: Match

    var body: some View {
        let p = match.prediction.probabilities
        GeometryReader { geo in
            HStack(spacing: 1) {
                Rectangle().fill(Color.green).frame(width: geo.size.width * p.home_win)
                Rectangle().fill(Color.gray).frame(width: geo.size.width * p.draw)
                Rectangle().fill(Color.orange).frame(width: geo.size.width * p.away_win)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 6)
    }
}

// MARK: - App / menu bar

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⚽"
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self

        popover.contentSize = NSSize(width: 420, height: 560)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ContentView())

        // Drives the rolling-ball reminders while the app is running.
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Store.shared.checkDueReminders()
        }
        Store.shared.checkDueReminders()
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // Show banners even while the app is frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}

@main
struct WorldCupReminderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
