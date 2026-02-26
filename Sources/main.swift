import AppKit

private enum Constants {
    static let defaultIntervalSeconds = 10
    static let intervalSecondsKey = "intervalSeconds"
    static let customSoundPathKey = "customSoundPath"
}

final class TimerController {
    private var timer: Timer?
    private var startDate: Date?
    private(set) var isRunning = false
    private var tickHandler: (() -> Void)?
    var interval: TimeInterval = TimeInterval(Constants.defaultIntervalSeconds)

    func start(onTick: @escaping () -> Void) {
        guard !isRunning else { return }
        isRunning = true
        startDate = Date()
        tickHandler = onTick
        scheduleNextTick()
    }

    private func scheduleNextTick() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self, self.isRunning else { return }
            self.tickHandler?()
            // Schedule the next reminder only after the current one is handled.
            self.scheduleNextTick()
        }
        timer?.tolerance = 2
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        startDate = nil
        tickHandler = nil
        isRunning = false
    }

    var elapsedText: String {
        guard isRunning else { return "Not running" }
        return "Running (\(formattedElapsed))"
    }

    var formattedElapsed: String {
        guard let startDate else { return "00:00:00" }
        let totalSeconds = Int(Date().timeIntervalSince(startDate))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
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
        timerController.interval = TimeInterval(intervalSeconds)
        configureMenuBar()
    }

    private func configureMenuBar() {
        if let button = statusItem.button {
            button.title = intervalShortText(intervalSeconds)
            button.toolTip = "\(intervalDescription(intervalSeconds)) reminder timer"
        }

        startItem.target = self
        stopItem.target = self
        setIntervalItem.target = self
        chooseSoundItem.target = self
        resetSoundItem.target = self

        statusMenu.addItem(stateItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(setIntervalItem)
        statusMenu.addItem(chooseSoundItem)
        statusMenu.addItem(resetSoundItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(startItem)
        statusMenu.addItem(stopItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: "Quit", action: #selector(quitApp), keyEquivalent: "q").target = self
        statusItem.menu = statusMenu

        refreshMenuState()
    }

    private func refreshMenuState() {
        stateItem.title = timerController.elapsedText
        statusItem.button?.title = timerController.isRunning ? timerController.formattedElapsed : intervalShortText(intervalSeconds)
        statusItem.button?.toolTip = "\(intervalDescription(intervalSeconds)) reminder timer"
        setIntervalItem.isEnabled = !timerController.isRunning
        startItem.isEnabled = !timerController.isRunning
        stopItem.isEnabled = timerController.isRunning
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
        alert.informativeText = "Enter a number of seconds."
        alert.alertStyle = .informational

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.placeholderString = "Seconds"
        input.stringValue = "\(intervalSeconds)"
        alert.accessoryView = input
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        let value = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seconds = Int(value), seconds > 0 else {
            showInvalidIntervalAlert()
            return
        }
        UserDefaults.standard.set(seconds, forKey: Constants.intervalSecondsKey)
        timerController.interval = TimeInterval(seconds)
        refreshMenuState()
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
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Time check"
        alert.informativeText = "\(intervalDescription(intervalSeconds)) have passed."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func showInvalidIntervalAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Invalid interval"
        alert.informativeText = "Please enter a whole number greater than zero."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func intervalShortText(_ seconds: Int) -> String {
        "\(seconds)s"
    }

    private func intervalDescription(_ seconds: Int) -> String {
        "\(seconds) seconds"
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
}

@main
struct PomodoroBarMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
