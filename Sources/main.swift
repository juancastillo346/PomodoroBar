import AppKit

private enum Constants {
    static let interval: TimeInterval = 10
    static let idleTitle = "10s"
    static let intervalDescription = "10 seconds"
    static let customSoundPathKey = "customSoundPath"
}

final class TimerController {
    private var timer: Timer?
    private var startDate: Date?
    private(set) var isRunning = false

    func start(onTick: @escaping () -> Void) {
        guard !isRunning else { return }
        isRunning = true
        startDate = Date()

        timer = Timer.scheduledTimer(withTimeInterval: Constants.interval, repeats: true) { _ in
            onTick()
        }
        timer?.tolerance = 2
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        startDate = nil
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenuBar()
    }

    private func configureMenuBar() {
        if let button = statusItem.button {
            button.title = Constants.idleTitle
            button.toolTip = "\(Constants.intervalDescription) reminder timer"
        }

        startItem.target = self
        stopItem.target = self
        chooseSoundItem.target = self
        resetSoundItem.target = self

        statusMenu.addItem(stateItem)
        statusMenu.addItem(.separator())
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
        statusItem.button?.title = timerController.isRunning ? timerController.formattedElapsed : Constants.idleTitle
        startItem.isEnabled = !timerController.isRunning
        stopItem.isEnabled = timerController.isRunning
        resetSoundItem.isEnabled = customSoundURL() != nil
    }

    @objc private func startTimer() {
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
        alert.informativeText = "\(Constants.intervalDescription) have passed."
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
