import AppKit

@MainActor
final class ReminderAlertWindowController: NSWindowController, NSWindowDelegate {
    private enum AlertKind {
        case unconfigured
        case rest
        case water
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let countdownLabel = NSTextField(labelWithString: "")
    private var countdownTimer: Timer?
    private var deadline: Date?
    private var completionButton: NSButton?
    private var onRestComplete: (() -> Void)?
    private var onWaterDone: (() -> Void)?
    private var onWaterSnooze: (() -> Void)?
    private var kind: AlertKind = .unconfigured
    private var isDismissed = false
    private var isResolving = false

    init(title: String, message: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 210),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.level = .modalPanel
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        window.delegate = self
        window.contentView = buildContentView(title: title, message: message)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureRest(deadline: Date, onComplete: @escaping () -> Void) {
        kind = .rest
        self.deadline = deadline
        onRestComplete = onComplete
        window?.standardWindowButton(.closeButton)?.toolTip = "关闭弹窗，休息倒计时继续"

        let button = NSButton(title: "休息完成", target: nil, action: nil)
        button.bezelStyle = .rounded
        button.isEnabled = false
        button.frame = NSRect(x: 280, y: 22, width: 112, height: 30)
        button.target = self
        button.action = #selector(completeRest)
        completionButton = button
        window?.contentView?.addSubview(button)

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCountdown()
            }
        }
        RunLoop.main.add(countdownTimer!, forMode: .common)
        updateCountdown()
    }

    func configureWater(snoozeMinutes: Int, onDone: @escaping () -> Void, onSnooze: @escaping () -> Void) {
        kind = .water
        onWaterDone = onDone
        onWaterSnooze = onSnooze
        window?.standardWindowButton(.closeButton)?.toolTip = "关闭并在 \(snoozeMinutes) 分钟后提醒"
        countdownLabel.stringValue = "现在站起来喝几口水。"

        let doneButton = NSButton(title: "我喝了", target: self, action: #selector(doneWater))
        doneButton.bezelStyle = .rounded
        doneButton.frame = NSRect(x: 284, y: 22, width: 108, height: 30)
        window?.contentView?.addSubview(doneButton)

        let snoozeButton = NSButton(title: "\(snoozeMinutes) 分钟后提醒", target: self, action: #selector(snoozeWater))
        snoozeButton.bezelStyle = .rounded
        snoozeButton.frame = NSRect(x: 132, y: 22, width: 140, height: 30)
        window?.contentView?.addSubview(snoozeButton)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !isResolving else { return true }

        switch kind {
        case .rest:
            if let deadline, deadline <= Date() {
                resolveRest(closeWindow: false)
            } else {
                isDismissed = true
            }
        case .water:
            resolveWater(using: onWaterSnooze, closeWindow: false)
        case .unconfigured:
            break
        }

        return true
    }

    func windowWillClose(_ notification: Notification) {
        if kind == .rest, isDismissed, !isResolving {
            return
        }
        stopCountdownTimer()
    }

    private func buildContentView(title: String, message: String) -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 210))

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.frame = NSRect(x: 28, y: 154, width: 364, height: 30)
        root.addSubview(titleLabel)

        messageLabel.stringValue = message
        messageLabel.font = .systemFont(ofSize: 14)
        messageLabel.frame = NSRect(x: 28, y: 100, width: 364, height: 44)
        root.addSubview(messageLabel)

        countdownLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        countdownLabel.frame = NSRect(x: 28, y: 60, width: 364, height: 26)
        root.addSubview(countdownLabel)

        return root
    }

    private func updateCountdown() {
        guard let deadline else { return }

        let remaining = max(0, Int(deadline.timeIntervalSinceNow))
        if remaining == 0 {
            countdownLabel.stringValue = "休息时间到了，点完成开始下一轮。"
            completionButton?.isEnabled = true
            stopCountdownTimer()
            if isDismissed {
                resolveRest(closeWindow: false)
            }
            return
        }

        let minutes = remaining / 60
        let seconds = remaining % 60
        countdownLabel.stringValue = String(format: "休息倒计时 %02d:%02d", minutes, seconds)
    }

    @objc private func completeRest(_ sender: NSButton) {
        resolveRest(closeWindow: true)
    }

    @objc private func doneWater(_ sender: NSButton) {
        resolveWater(using: onWaterDone, closeWindow: true)
    }

    @objc private func snoozeWater(_ sender: NSButton) {
        resolveWater(using: onWaterSnooze, closeWindow: true)
    }

    private func resolveRest(closeWindow: Bool) {
        guard !isResolving else { return }
        isResolving = true
        stopCountdownTimer()
        let completion = onRestComplete
        onRestComplete = nil
        completion?()

        if closeWindow {
            window?.close()
        }
    }

    private func resolveWater(using action: (() -> Void)?, closeWindow: Bool) {
        guard !isResolving else { return }
        isResolving = true
        let completion = action
        onWaterDone = nil
        onWaterSnooze = nil
        completion?()

        if closeWindow {
            window?.close()
        }
    }

    private func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }
}
