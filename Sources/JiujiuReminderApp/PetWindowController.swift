import AppKit

@MainActor
protocol PetWindowControllerDelegate: AnyObject {
    func petWindowDidRequestTogglePause()
    func petWindowDidRequestResetCycle()
    func petWindowDidRequestSettings()
    func petWindowDidRequestLaunchAtLoginToggle()
    func petWindowDidRequestDisplayMode(_ mode: PetDisplayMode)
    func petWindowDidRequestQuit()
    func petWindowStatusText() -> String
    func petWindowIsPaused() -> Bool
    func petWindowLaunchAtLoginEnabled() -> Bool
    func petWindowDisplayMode() -> PetDisplayMode
    func petWindowDidMove(to point: NSPoint)
}

@MainActor
final class PetWindowController: NSWindowController, NSMenuDelegate {
    weak var delegate: PetWindowControllerDelegate?

    private let petView: PetView

    init(initialPosition: NSPoint?) {
        let size = SpriteSheet.cellSize
        petView = PetView(frame: NSRect(origin: .zero, size: size))

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let origin = initialPosition ?? NSPoint(
            x: screenFrame.maxX - size.width - 48,
            y: screenFrame.minY + 48
        )

        let window = PetWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = petView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false

        super.init(window: window)

        petView.onDragFinished = { [weak self] point in
            self?.delegate?.petWindowDidMove(to: point)
        }
        petView.menu = makeMenu()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.orderFrontRegardless()
        petView.startAnimating()
    }

    func setDisplayMode(_ mode: PetDisplayMode) {
        petView.setDisplayMode(mode)
    }

    func setActivityPhase(_ phase: PetActivityPhase) {
        petView.setActivityPhase(phase)
    }

    func pulse() {
        petView.playTemporary(state: .waving, duration: 1.8)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: delegate?.petWindowStatusText() ?? "准备中", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let pauseTitle = (delegate?.petWindowIsPaused() ?? false) ? "继续" : "暂停"
        menu.addItem(NSMenuItem(title: pauseTitle, action: #selector(togglePause), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "重置本轮", action: #selector(resetCycle), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "设置时间...", action: #selector(openSettings), keyEquivalent: ""))
        menu.addItem(makeDisplayModeMenuItem())

        let launchItem = NSMenuItem(title: "开机自动启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.state = (delegate?.petWindowLaunchAtLoginEnabled() ?? false) ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 玖玖提醒", action: #selector(quit), keyEquivalent: "q"))
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        return menu
    }

    private func makeDisplayModeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "桌宠状态", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let currentMode = delegate?.petWindowDisplayMode() ?? .automatic

        for mode in PetDisplayMode.allCases {
            let modeItem = NSMenuItem(title: mode.title, action: #selector(selectDisplayMode(_:)), keyEquivalent: "")
            modeItem.representedObject = mode.rawValue
            modeItem.state = mode == currentMode ? .on : .off
            submenu.addItem(modeItem)
        }

        item.submenu = submenu
        return item
    }

    @objc private func togglePause() {
        delegate?.petWindowDidRequestTogglePause()
    }

    @objc private func resetCycle() {
        delegate?.petWindowDidRequestResetCycle()
    }

    @objc private func openSettings() {
        delegate?.petWindowDidRequestSettings()
    }

    @objc private func toggleLaunchAtLogin() {
        delegate?.petWindowDidRequestLaunchAtLoginToggle()
    }

    @objc private func selectDisplayMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = PetDisplayMode(rawValue: rawValue) else {
            return
        }

        delegate?.petWindowDidRequestDisplayMode(mode)
    }

    @objc private func quit() {
        delegate?.petWindowDidRequestQuit()
    }
}

@MainActor
final class PetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class PetView: NSView {
    var onDragFinished: ((NSPoint) -> Void)?

    private let spriteSheet = SpriteSheet()
    private var timer: Timer?
    private var frameIndex = 0
    private var state: PetAnimationState = .idle
    private var displayMode: PetDisplayMode = .automatic
    private var activityPhase: PetActivityPhase = .working
    private var carouselIndex = 0
    private var carouselTick = 0
    private var dragStartWindowOrigin: NSPoint?
    private var dragStartMouseLocation: NSPoint?

    override var isFlipped: Bool { true }

    func startAnimating() {
        guard timer == nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.advanceAnimation()
                self.needsDisplay = true
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func setDisplayMode(_ mode: PetDisplayMode) {
        displayMode = mode
        resetAnimation()
    }

    func setActivityPhase(_ phase: PetActivityPhase) {
        guard activityPhase != phase else { return }

        activityPhase = phase
        resetAnimation()
    }

    func playTemporary(state newState: PetAnimationState, duration: TimeInterval) {
        state = newState
        frameIndex = 0
        needsDisplay = true

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.resetAnimation()
        }
    }

    private func advanceAnimation() {
        if shouldCarousel {
            carouselTick += 1
            if carouselTick >= max(12, state.frames * 2) {
                carouselTick = 0
                carouselIndex = (carouselIndex + 1) % PetDisplayMode.restCarouselStates.count
                state = PetDisplayMode.restCarouselStates[carouselIndex]
                frameIndex = 0
                return
            }
        }

        frameIndex += 1
    }

    private func resetAnimation() {
        carouselIndex = 0
        carouselTick = 0
        frameIndex = 0
        state = resolvedState()
        needsDisplay = true
    }

    private var shouldCarousel: Bool {
        displayMode == .restCarousel || (displayMode == .automatic && activityPhase == .resting)
    }

    private func resolvedState() -> PetAnimationState {
        if let fixed = displayMode.fixedState {
            return fixed
        }

        if shouldCarousel {
            return PetDisplayMode.restCarouselStates[carouselIndex]
        }

        switch activityPhase {
        case .working:
            return .working
        case .resting:
            return PetDisplayMode.restCarouselStates[carouselIndex]
        case .paused:
            return .idle
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let spriteSheet else {
            NSColor.systemGray.withAlphaComponent(0.22).setFill()
            bounds.fill()
            return
        }

        spriteSheet.draw(state: state, frame: frameIndex, in: bounds)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func mouseDown(with event: NSEvent) {
        dragStartWindowOrigin = window?.frame.origin
        dragStartMouseLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window,
              let startOrigin = dragStartWindowOrigin,
              let startMouse = dragStartMouseLocation else {
            return
        }

        let currentMouse = NSEvent.mouseLocation
        let dx = currentMouse.x - startMouse.x
        let dy = currentMouse.y - startMouse.y
        window.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        if let point = window?.frame.origin {
            onDragFinished?(point)
        }
        dragStartWindowOrigin = nil
        dragStartMouseLocation = nil
    }
}
