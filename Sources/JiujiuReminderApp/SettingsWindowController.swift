import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    var onSave: ((ReminderSettings) -> Void)?
    var onCancelFirstRun: (() -> Void)?

    private var settings: ReminderSettings
    private let isFirstRun: Bool
    private let workField = NSTextField()
    private let restField = NSTextField()
    private let waterField = NSTextField()
    private let errorLabel = NSTextField(labelWithString: "")

    init(settings: ReminderSettings, isFirstRun: Bool) {
        self.settings = settings
        self.isFirstRun = isFirstRun

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 270),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = isFirstRun ? "设置玖玖提醒" : "设置时间"
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()

        super.init(window: window)

        window.delegate = self
        window.contentView = buildContentView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isFirstRun {
            onCancelFirstRun?()
        }
        return true
    }

    private func buildContentView() -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 270))

        let title = NSTextField(labelWithString: isFirstRun ? "先设置你的默认节奏" : "调整提醒时间")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.frame = NSRect(x: 24, y: 220, width: 312, height: 24)
        root.addSubview(title)

        configureNumberField(workField, value: settings.workMinutes)
        configureNumberField(restField, value: settings.restMinutes)
        configureNumberField(waterField, value: settings.waterIntervalMinutes)

        addRow(to: root, label: "工作时长（分钟）", field: workField, y: 172)
        addRow(to: root, label: "休息时长（分钟）", field: restField, y: 126)
        addRow(to: root, label: "喝水间隔（分钟）", field: waterField, y: 80)

        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.frame = NSRect(x: 24, y: 50, width: 312, height: 18)
        root.addSubview(errorLabel)

        let saveButton = NSButton(title: isFirstRun ? "开始使用" : "保存", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.frame = NSRect(x: 232, y: 18, width: 104, height: 28)
        root.addSubview(saveButton)

        let cancelButton = NSButton(title: isFirstRun ? "退出" : "取消", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.frame = NSRect(x: 144, y: 18, width: 80, height: 28)
        root.addSubview(cancelButton)

        return root
    }

    private func addRow(to root: NSView, label: String, field: NSTextField, y: CGFloat) {
        let labelView = NSTextField(labelWithString: label)
        labelView.frame = NSRect(x: 24, y: y + 5, width: 160, height: 20)
        root.addSubview(labelView)

        field.frame = NSRect(x: 194, y: y, width: 96, height: 28)
        root.addSubview(field)
    }

    private func configureNumberField(_ field: NSTextField, value: Int) {
        field.integerValue = value
        field.alignment = .right
        field.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
    }

    @objc private func save() {
        let work = workField.integerValue
        let rest = restField.integerValue
        let water = waterField.integerValue

        guard (1...240).contains(work),
              (1...120).contains(rest),
              (1...240).contains(water) else {
            errorLabel.stringValue = "请输入 1 到 240 内的分钟数，休息最多 120 分钟。"
            return
        }

        settings.workMinutes = work
        settings.restMinutes = rest
        settings.waterIntervalMinutes = water
        settings.hasCompletedFirstRun = true
        onSave?(settings)
        window?.close()
    }

    @objc private func cancel() {
        if isFirstRun {
            onCancelFirstRun?()
        }
        window?.close()
    }
}
