import AppKit
import UserNotifications

private enum Constants {
    static let appName = "Focus Timer"
    static let defaultIntervalSeconds = 30 * 60
    static let preset30MinutesSeconds = 30 * 60
    static let preset1HourSeconds = 60 * 60
    static let intervalSecondsKey = "intervalSeconds"
    static let customSoundPathKey = "customSoundPath"
}

final class TimerController {
    private var timer: Timer?
    private var runStartDate: Date?
    private var accumulatedElapsed: TimeInterval = 0
    private var nextReminderDate: Date?
    private var remainingUntilNextReminder: TimeInterval = 0
    private(set) var isRunning = false
    private(set) var isPaused = false
    private var tickHandler: (() -> Void)?
    var interval: TimeInterval = TimeInterval(Constants.defaultIntervalSeconds)
    var isActive: Bool { isRunning || isPaused }

    func start(onTick: @escaping () -> Void) {
        guard !isRunning, !isPaused else { return }
        isRunning = true
        isPaused = false
        runStartDate = Date()
        accumulatedElapsed = 0
        remainingUntilNextReminder = interval
        tickHandler = onTick
        scheduleNextTick(after: interval)
    }

    private func scheduleNextTick(after delay: TimeInterval) {
        timer?.invalidate()
        let safeDelay = max(1, delay)
        nextReminderDate = Date().addingTimeInterval(safeDelay)
        timer = Timer.scheduledTimer(withTimeInterval: safeDelay, repeats: false) { [weak self] _ in
            guard let self, self.isRunning, !self.isPaused else { return }
            self.remainingUntilNextReminder = self.interval
            self.tickHandler?()
            // Schedule the next reminder only after the current one is handled.
            self.scheduleNextTick(after: self.interval)
        }
        timer?.tolerance = 2
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        let now = Date()
        if let runStartDate {
            accumulatedElapsed += now.timeIntervalSince(runStartDate)
        }
        remainingUntilNextReminder = max(1, nextReminderDate?.timeIntervalSince(now) ?? interval)
        timer?.invalidate()
        timer = nil
        nextReminderDate = nil
        runStartDate = nil
        isRunning = false
        isPaused = true
    }

    func resume() {
        guard isPaused, !isRunning else { return }
        isPaused = false
        isRunning = true
        runStartDate = Date()
        let delay = remainingUntilNextReminder > 0 ? remainingUntilNextReminder : interval
        scheduleNextTick(after: delay)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        runStartDate = nil
        accumulatedElapsed = 0
        nextReminderDate = nil
        remainingUntilNextReminder = 0
        tickHandler = nil
        isRunning = false
        isPaused = false
    }

    var elapsedText: String {
        if isRunning {
            return "Running (\(formattedElapsed))"
        }
        if isPaused {
            return "Paused (\(formattedElapsed))"
        }
        return "Not running"
    }

    var formattedElapsed: String {
        var totalElapsed = accumulatedElapsed
        if isRunning, let runStartDate {
            totalElapsed += Date().timeIntervalSince(runStartDate)
        }
        let totalSeconds = Int(totalElapsed)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let timerController = TimerController()
    private var uiRefreshTimer: Timer?

    private let statusMenu = NSMenu()
    private let stateItem = NSMenuItem(title: "Not running", action: nil, keyEquivalent: "")
    private lazy var setIntervalItem = NSMenuItem(
        title: "Set Interval...",
        action: #selector(setIntervalPrompt),
        keyEquivalent: ""
    )
    private lazy var presetItem = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
    private let presetMenu = NSMenu()
    private lazy var preset30MinItem = NSMenuItem(
        title: "30 Minutes",
        action: #selector(setPreset30Minutes),
        keyEquivalent: ""
    )
    private lazy var preset1HourItem = NSMenuItem(
        title: "1 Hour",
        action: #selector(setPreset1Hour),
        keyEquivalent: ""
    )
    private lazy var chooseSoundItem = NSMenuItem(
        title: "Choose Sound...",
        action: #selector(chooseCustomSound),
        keyEquivalent: ""
    )
    private lazy var resetSoundItem = NSMenuItem(
        title: "Use Default Sound",
        action: #selector(resetCustomSound),
        keyEquivalent: ""
    )
    private lazy var startItem = NSMenuItem(
        title: "Start",
        action: #selector(startTimer),
        keyEquivalent: "s"
    )
    private lazy var pauseResumeItem = NSMenuItem(
        title: "Pause",
        action: #selector(togglePauseResume),
        keyEquivalent: "p"
    )
    private lazy var stopItem = NSMenuItem(
        title: "Stop",
        action: #selector(stopTimer),
        keyEquivalent: "x"
    )
    
    private var intervalSeconds: Int {
        let saved = UserDefaults.standard.integer(forKey: Constants.intervalSecondsKey)
        return saved > 0 ? saved : Constants.defaultIntervalSeconds
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if UserDefaults.standard.object(forKey: Constants.intervalSecondsKey) == nil {
            UserDefaults.standard.set(Constants.defaultIntervalSeconds, forKey: Constants.intervalSecondsKey)
        }
        timerController.interval = TimeInterval(intervalSeconds)
        configureNotifications()
        configureMenuBar()
    }

    private func configureNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        Task { @MainActor in
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                if granted {
                    sendSystemNotification(title: Constants.appName, body: "Notifications are enabled.")
                } else {
                    showNotificationPermissionHelp()
                }
            case .denied:
                showNotificationPermissionHelp()
            case .authorized, .provisional, .ephemeral:
                break
            @unknown default:
                break
            }
        }
    }

    private func configureMenuBar() {
        if let button = statusItem.button {
            button.title = intervalShortText(intervalSeconds)
            button.toolTip = "\(intervalDescription(intervalSeconds)) reminder timer"
        }

        startItem.target = self
        pauseResumeItem.target = self
        stopItem.target = self
        setIntervalItem.target = self
        preset30MinItem.target = self
        preset1HourItem.target = self
        chooseSoundItem.target = self
        resetSoundItem.target = self

        presetMenu.addItem(preset30MinItem)
        presetMenu.addItem(preset1HourItem)
        presetItem.submenu = presetMenu

        statusMenu.addItem(stateItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(presetItem)
        statusMenu.addItem(setIntervalItem)
        statusMenu.addItem(chooseSoundItem)
        statusMenu.addItem(resetSoundItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(startItem)
        statusMenu.addItem(pauseResumeItem)
        statusMenu.addItem(stopItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: "Quit", action: #selector(quitApp), keyEquivalent: "q").target = self
        statusItem.menu = statusMenu

        refreshMenuState()
    }

    private func refreshMenuState() {
        stateItem.title = timerController.elapsedText
        statusItem.button?.title = timerController.isActive ? timerController.formattedElapsed : intervalShortText(intervalSeconds)
        statusItem.button?.toolTip = "\(intervalDescription(intervalSeconds)) reminder timer"
        let timerInactive = !timerController.isActive
        setIntervalItem.isEnabled = timerInactive
        preset30MinItem.isEnabled = timerInactive
        preset1HourItem.isEnabled = timerInactive
        startItem.isEnabled = timerInactive
        pauseResumeItem.isEnabled = timerController.isActive
        pauseResumeItem.title = timerController.isPaused ? "Resume" : "Pause"
        stopItem.isEnabled = timerController.isActive
        resetSoundItem.isEnabled = customSoundURL() != nil
    }

    @objc private func startTimer() {
        timerController.interval = TimeInterval(intervalSeconds)
        timerController.start { [weak self] in
            self?.sendReminderNotification()
            self?.refreshMenuState()
        }
        startUIRefreshTimer()
        refreshMenuState()
    }

    @objc private func stopTimer() {
        timerController.stop()
        stopUIRefreshTimer()
        refreshMenuState()
    }

    @objc private func togglePauseResume() {
        if timerController.isRunning {
            timerController.pause()
            stopUIRefreshTimer()
        } else if timerController.isPaused {
            timerController.resume()
            startUIRefreshTimer()
        }
        refreshMenuState()
    }

    @objc private func setPreset30Minutes() {
        saveIntervalSeconds(Constants.preset30MinutesSeconds)
    }

    @objc private func setPreset1Hour() {
        saveIntervalSeconds(Constants.preset1HourSeconds)
    }

    @objc private func quitApp() {
        stopUIRefreshTimer()
        timerController.stop()
        NSApp.terminate(nil)
    }

    @objc private func chooseCustomSound() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        panel.message = "Choose a reminder sound"

        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: Constants.customSoundPathKey)
            refreshMenuState()
        }
    }

    @objc private func resetCustomSound() {
        UserDefaults.standard.removeObject(forKey: Constants.customSoundPathKey)
        refreshMenuState()
    }
    
    @objc private func setIntervalPrompt() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Set timer interval"
        alert.informativeText = "Enter minutes and seconds."
        alert.alertStyle = .informational

        let total = intervalSeconds
        let currentMinutes = total / 60
        let currentSeconds = total % 60

        let minutesInput = NSTextField(frame: NSRect(x: 0, y: 0, width: 84, height: 24))
        minutesInput.stringValue = "\(currentMinutes)"
        minutesInput.alignment = .right
        minutesInput.focusRingType = .default
        minutesInput.controlSize = .regular

        let secondsInput = NSTextField(frame: NSRect(x: 0, y: 0, width: 84, height: 24))
        secondsInput.stringValue = "\(currentSeconds)"
        secondsInput.alignment = .right
        secondsInput.focusRingType = .default
        secondsInput.controlSize = .regular

        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 0
        formatter.maximum = 9999
        formatter.generatesDecimalNumbers = false
        minutesInput.formatter = formatter
        secondsInput.formatter = formatter

        let minutesLabel = NSTextField(labelWithString: "Minutes")
        let secondsLabel = NSTextField(labelWithString: "Seconds")
        minutesLabel.alignment = .left
        secondsLabel.alignment = .left

        let grid = NSGridView(views: [
            [minutesLabel, minutesInput],
            [secondsLabel, secondsInput]
        ])
        grid.columnSpacing = 10
        grid.rowSpacing = 8
        grid.frame = NSRect(x: 0, y: 0, width: 230, height: 62)
        alert.accessoryView = grid
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        let minutesValue = minutesInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondsValue = secondsInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let minutes = Int(minutesValue) ?? -1
        let seconds = Int(secondsValue) ?? -1
        guard minutes >= 0, seconds >= 0 else {
            showInvalidIntervalAlert()
            return
        }
        let totalSeconds = (minutes * 60) + seconds
        guard totalSeconds > 0 else {
            showInvalidIntervalAlert()
            return
        }
        saveIntervalSeconds(totalSeconds)
    }

    private func startUIRefreshTimer() {
        uiRefreshTimer?.invalidate()
        uiRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshMenuState()
        }
        uiRefreshTimer?.tolerance = 0.1
    }

    private func stopUIRefreshTimer() {
        uiRefreshTimer?.invalidate()
        uiRefreshTimer = nil
    }

    private func sendReminderNotification() {
        playReminderSound()
        sendSystemNotification(
            title: Constants.appName,
            body: "\(intervalDescription(intervalSeconds)) have passed."
        )
    }

    private func sendSystemNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func showNotificationPermissionHelp() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Notifications are disabled"
        alert.informativeText = "Enable notifications for \(Constants.appName) in System Settings to receive timer banners."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func showInvalidIntervalAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Invalid interval"
        alert.informativeText = "Please enter non-negative whole numbers, with at least one value greater than zero."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func intervalShortText(_ seconds: Int) -> String {
        if seconds % 3600 == 0 {
            return "\(seconds / 3600)h"
        }
        if seconds % 60 == 0 {
            return "\(seconds / 60)m"
        }
        if seconds >= 60 {
            let minutes = seconds / 60
            let remainder = seconds % 60
            return "\(minutes)m \(remainder)s"
        }
        return "\(seconds)s"
    }

    private func intervalDescription(_ seconds: Int) -> String {
        if seconds % 3600 == 0 {
            let hours = seconds / 3600
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        if seconds % 60 == 0 {
            let minutes = seconds / 60
            return minutes == 1 ? "1 min" : "\(minutes) mins"
        }
        if seconds >= 60 {
            let minutes = seconds / 60
            let remainder = seconds % 60
            let minutePart = minutes == 1 ? "1 min" : "\(minutes) mins"
            let secondPart = remainder == 1 ? "1 sec" : "\(remainder) secs"
            return "\(minutePart) \(secondPart)"
        }
        return seconds == 1 ? "1 sec" : "\(seconds) secs"
    }

    private func playReminderSound() {
        if let customURL = customSoundURL(),
           let customSound = NSSound(contentsOf: customURL, byReference: true) {
            customSound.play()
            return
        }

        if let sound = NSSound(named: NSSound.Name("Glass")) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    private func customSoundURL() -> URL? {
        guard let customPath = UserDefaults.standard.string(forKey: Constants.customSoundPathKey),
              FileManager.default.fileExists(atPath: customPath) else {
            return nil
        }
        return URL(fileURLWithPath: customPath)
    }

    private func saveIntervalSeconds(_ seconds: Int) {
        UserDefaults.standard.set(seconds, forKey: Constants.intervalSecondsKey)
        timerController.interval = TimeInterval(seconds)
        refreshMenuState()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}

@main
struct FocusTimerMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
