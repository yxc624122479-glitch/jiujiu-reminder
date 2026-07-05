import AppKit

@MainActor
protocol PetWindowControllerDelegate: AnyObject {
    func petWindowDidRequestTogglePause()
    func petWindowDidRequestResetCycle()
    func petWindowDidRequestSettings()
    func petWindowDidRequestLaunchAtLoginToggle()
    func petWindowDidRequestDisplayMode(_ mode: PetDisplayMode)
    func petWindowDidRequestSkin(_ skinID: PetSkinID)
    func petWindowDidRequestScale(_ scale: CGFloat)
    func petWindowDidRequestQuit()
    func petWindowStatusText() -> String
    func petWindowIsPaused() -> Bool
    func petWindowLaunchAtLoginEnabled() -> Bool
    func petWindowDisplayMode() -> PetDisplayMode
    func petWindowSkinID() -> PetSkinID
    func petWindowScale() -> CGFloat
    func petWindowDidMove(to point: NSPoint)
}

@MainActor
final class PetWindowController: NSWindowController, NSMenuDelegate {
    weak var delegate: PetWindowControllerDelegate?

    private let petView: PetView
    private var interactionSession: PetInteractionSession?

    var activeSkinID: PetSkinID { petView.skin.id }

    init(initialPosition: NSPoint?, scale: CGFloat, skinID: PetSkinID) {
        petView = PetView(skinID: skinID)
        let size = Self.scaledSize(baseSize: petView.skin.displaySize, scale: scale)
        petView.frame = NSRect(origin: .zero, size: size)
        petView.autoresizingMask = [.width, .height]

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let preferredOrigin = initialPosition ?? NSPoint(
            x: screenFrame.maxX - size.width - 48,
            y: screenFrame.minY + 48
        )
        let origin = Self.clampedOrigin(preferredOrigin, size: size, visibleFrame: screenFrame)

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

        petView.onDragStarted = { [weak self] in
            self?.stopInteraction(animated: false)
        }
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
        petView.setDisplayMode(mode.normalized(for: petView.skin))
    }

    func setActivityPhase(_ phase: PetActivityPhase) {
        petView.setActivityPhase(phase)
    }

    func setSkin(_ skinID: PetSkinID, displayMode: PetDisplayMode, scale: CGFloat) -> PetDisplayMode? {
        stopInteraction(animated: false)
        let oldBaseSize = petView.skin.displaySize
        guard petView.setSkin(skinID) else { return nil }

        let normalizedMode = displayMode.normalized(for: petView.skin)
        petView.setDisplayMode(normalizedMode)
        resizeWindow(from: oldBaseSize, to: petView.skin.displaySize, scale: scale)
        return normalizedMode
    }

    func setScale(_ scale: CGFloat) {
        stopInteraction(animated: false)
        guard let window else { return }

        let newSize = Self.scaledSize(baseSize: petView.skin.displaySize, scale: scale)
        let oldFrame = window.frame
        let preferredOrigin = NSPoint(
            x: oldFrame.midX - newSize.width / 2,
            y: oldFrame.midY - newSize.height / 2
        )
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? oldFrame
        let origin = Self.clampedOrigin(preferredOrigin, size: newSize, visibleFrame: visibleFrame)
        let newFrame = NSRect(origin: origin, size: newSize)

        window.setFrame(newFrame, display: true, animate: true)
        delegate?.petWindowDidMove(to: origin)
    }

    func pulse(_ cue: PetReminderCue = .generic) {
        stopInteraction(animated: true)
        let action = petView.skin.cueAction(for: cue)
        let fullCycleDuration = petView.skin.clip(for: action).map { $0.frameDuration * Double($0.frames) } ?? 1.8
        petView.playTemporary(action: action, duration: max(1.8, fullCycleDuration))
    }

    func stopInteraction(animated: Bool = true) {
        interactionSession?.stop(animated: animated)
        interactionSession = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: delegate?.petWindowStatusText() ?? "准备中", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if let session = interactionSession, session.isActive {
            let interactionStatus = NSMenuItem(title: "互动中", action: nil, keyEquivalent: "")
            interactionStatus.isEnabled = false
            menu.addItem(interactionStatus)
        }

        menu.addItem(.separator())

        let pauseTitle = (delegate?.petWindowIsPaused() ?? false) ? "继续" : "暂停"
        menu.addItem(NSMenuItem(title: pauseTitle, action: #selector(togglePause), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "重置本轮", action: #selector(resetCycle), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "设置时间...", action: #selector(openSettings), keyEquivalent: ""))
        menu.addItem(makeDisplayModeMenuItem())
        menu.addItem(makeSkinMenuItem())
        menu.addItem(makeSizeMenuItem())
        menu.addItem(makeInteractionMenuItem())

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
        let item = NSMenuItem(title: "桌宠动作", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let currentMode = (delegate?.petWindowDisplayMode() ?? .automatic).normalized(for: petView.skin)

        addDisplayMode(.automatic, title: "自动跟随", currentMode: currentMode, to: submenu)
        addDisplayMode(.carousel, title: petView.skin.id == .classic ? "休息轮播" : "生活轮播", currentMode: currentMode, to: submenu)
        submenu.addItem(.separator())

        for action in petView.skin.manualActions {
            guard let clip = petView.skin.clip(for: action) else { continue }
            addDisplayMode(.action(action), title: clip.title, currentMode: currentMode, to: submenu)
        }

        item.submenu = submenu
        return item
    }

    private func addDisplayMode(_ mode: PetDisplayMode, title: String, currentMode: PetDisplayMode, to menu: NSMenu) {
        let modeItem = NSMenuItem(title: title, action: #selector(selectDisplayMode(_:)), keyEquivalent: "")
        modeItem.representedObject = mode.persistedValue
        modeItem.state = mode == currentMode ? .on : .off
        menu.addItem(modeItem)
    }

    private func makeSkinMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "桌宠皮肤", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let currentSkinID = delegate?.petWindowSkinID() ?? petView.skin.id

        for skinID in PetSkinID.allCases {
            let skinItem = NSMenuItem(title: skinID.title, action: #selector(selectSkin(_:)), keyEquivalent: "")
            skinItem.representedObject = skinID.rawValue
            skinItem.state = skinID == currentSkinID ? .on : .off
            submenu.addItem(skinItem)
        }

        item.submenu = submenu
        return item
    }

    private func makeSizeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "桌宠大小", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let currentPreset = PetSizePreset.closest(to: delegate?.petWindowScale() ?? PetSizePreset.standard.scale)

        for preset in PetSizePreset.allCases {
            let presetItem = NSMenuItem(title: preset.title, action: #selector(selectScale(_:)), keyEquivalent: "")
            presetItem.representedObject = preset.rawValue
            presetItem.state = preset == currentPreset ? .on : .off
            submenu.addItem(presetItem)
        }

        item.submenu = submenu
        return item
    }

    private func makeInteractionMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "互动", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let supported = petView.skin.chaseInteractionAction != nil && petView.skin.treatInteractionAction != nil

        let wandItem = NSMenuItem(title: "逗猫棒（30 秒）", action: #selector(startWandInteraction), keyEquivalent: "")
        wandItem.isEnabled = supported
        submenu.addItem(wandItem)

        let treatItem = NSMenuItem(title: "投喂猫条", action: #selector(startTreatInteraction), keyEquivalent: "")
        treatItem.isEnabled = supported
        submenu.addItem(treatItem)

        let stopItem = NSMenuItem(title: "停止互动", action: #selector(stopCurrentInteraction), keyEquivalent: "")
        stopItem.isEnabled = interactionSession?.isActive == true
        submenu.addItem(stopItem)

        if !supported {
            let hint = NSMenuItem(title: "切换到真实玖玖后可用", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            submenu.addItem(.separator())
            submenu.addItem(hint)
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
        guard let persistedValue = sender.representedObject as? String else { return }
        delegate?.petWindowDidRequestDisplayMode(PetDisplayMode(persistedValue: persistedValue))
    }

    @objc private func selectSkin(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let skinID = PetSkinID(rawValue: rawValue) else {
            return
        }
        delegate?.petWindowDidRequestSkin(skinID)
    }

    @objc private func selectScale(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let preset = PetSizePreset(rawValue: rawValue) else {
            return
        }
        delegate?.petWindowDidRequestScale(preset.scale)
    }

    @objc private func startWandInteraction() {
        startInteraction(.wand)
    }

    @objc private func startTreatInteraction() {
        startInteraction(.treat)
    }

    @objc private func stopCurrentInteraction() {
        stopInteraction(animated: true)
    }

    @objc private func quit() {
        delegate?.petWindowDidRequestQuit()
    }

    private func startInteraction(_ mode: PetInteractionMode) {
        guard let window,
              let chaseAction = petView.skin.chaseInteractionAction,
              let treatAction = petView.skin.treatInteractionAction,
              let propImage = petView.interactionPropImage(for: mode) else {
            return
        }

        stopInteraction(animated: false)
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        let session = PetInteractionSession(
            mode: mode,
            petWindow: window,
            anchorOrigin: window.frame.origin,
            visibleFrame: visibleFrame,
            chaseAction: chaseAction,
            observeAction: petView.skin.supports(.observing) ? .observing : chaseAction,
            treatAction: treatAction,
            propImage: propImage
        )
        session.delegate = self
        interactionSession = session
        session.start()
    }

    private func resizeWindow(from oldBaseSize: NSSize, to newBaseSize: NSSize, scale: CGFloat) {
        guard let window else { return }
        let newSize = Self.scaledSize(baseSize: newBaseSize, scale: scale)
        let oldFrame = window.frame
        let preferredOrigin = NSPoint(
            x: oldFrame.midX - newSize.width / 2,
            y: oldFrame.midY - newSize.height / 2
        )
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? oldFrame
        let origin = Self.clampedOrigin(preferredOrigin, size: newSize, visibleFrame: visibleFrame)
        window.setFrame(NSRect(origin: origin, size: newSize), display: true, animate: oldBaseSize != newBaseSize)
        delegate?.petWindowDidMove(to: origin)
    }

    private static func scaledSize(baseSize: NSSize, scale: CGFloat) -> NSSize {
        NSSize(width: baseSize.width * scale, height: baseSize.height * scale)
    }

    private static func clampedOrigin(_ origin: NSPoint, size: NSSize, visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(origin.x, visibleFrame.minX), max(visibleFrame.minX, visibleFrame.maxX - size.width)),
            y: min(max(origin.y, visibleFrame.minY), max(visibleFrame.minY, visibleFrame.maxY - size.height))
        )
    }
}

extension PetWindowController: PetInteractionSessionDelegate {
    func petInteractionDidRequestAction(_ action: PetActionID, flippedHorizontally: Bool) {
        petView.setInteractionAction(action, flippedHorizontally: flippedHorizontally)
    }

    func petInteractionDidClearAction() {
        petView.clearInteractionAction()
    }
}

@MainActor
final class PetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class PetView: NSView {
    var onDragStarted: (() -> Void)?
    var onDragFinished: ((NSPoint) -> Void)?

    private(set) var skin: PetSkinDefinition
    private var spriteSheet: SpriteSheet
    private var timer: Timer?
    private var frameIndex = 0
    private var action: PetActionID
    private var previousAction: PetActionID?
    private var previousFrameIndex = 0
    private var previousFlip = false
    private var transitionElapsed: TimeInterval = 0
    private var transitionDuration: TimeInterval {
        skin.id == .realistic ? 0.22 : 0.14
    }
    private var frameElapsed: TimeInterval = 0
    private var completedLoops = 0
    private var lastTickTime: TimeInterval?
    private var temporaryAction: PetActionID?
    private var temporaryDeadline: Date?
    private var interactionAction: PetActionID?
    private var interactionFlip = false
    private var displayMode: PetDisplayMode = .automatic
    private var activityPhase: PetActivityPhase = .working
    private var carouselIndex = 0
    private var dragStartWindowOrigin: NSPoint?
    private var dragStartMouseLocation: NSPoint?

    override var isFlipped: Bool { true }

    init(skinID: PetSkinID) {
        let requestedSkin = PetSkinDefinition.definition(for: skinID)
        if let requestedSheet = SpriteSheet(skin: requestedSkin) {
            skin = requestedSkin
            spriteSheet = requestedSheet
        } else {
            skin = .classic
            spriteSheet = SpriteSheet(skin: .classic)!
        }
        action = skin.workingAction
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startAnimating() {
        guard timer == nil else { return }

        lastTickTime = ProcessInfo.processInfo.systemUptime
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.advanceAnimation(at: ProcessInfo.processInfo.systemUptime)
            }
        }
        timer?.tolerance = 1.0 / 120.0
        RunLoop.main.add(timer!, forMode: .common)
    }

    func setSkin(_ skinID: PetSkinID) -> Bool {
        let newSkin = PetSkinDefinition.definition(for: skinID)
        guard let newSheet = SpriteSheet(skin: newSkin) else { return false }

        skin = newSkin
        spriteSheet = newSheet
        displayMode = displayMode.normalized(for: newSkin)
        interactionAction = nil
        temporaryAction = nil
        temporaryDeadline = nil
        carouselIndex = 0
        action = resolvedAction()
        previousAction = nil
        frameIndex = 0
        frameElapsed = 0
        completedLoops = 0
        needsDisplay = true
        return true
    }

    func setDisplayMode(_ mode: PetDisplayMode) {
        displayMode = mode.normalized(for: skin)
        resetAnimation()
    }

    func setActivityPhase(_ phase: PetActivityPhase) {
        guard activityPhase != phase else { return }
        activityPhase = phase
        resetAnimation()
    }

    func playTemporary(action newAction: PetActionID, duration: TimeInterval) {
        guard skin.supports(newAction) else { return }
        temporaryAction = newAction
        temporaryDeadline = Date().addingTimeInterval(duration)
        transition(to: newAction)
    }

    func setInteractionAction(_ newAction: PetActionID, flippedHorizontally: Bool) {
        guard skin.supports(newAction) else { return }
        interactionAction = newAction
        interactionFlip = flippedHorizontally
        if action != newAction {
            transition(to: newAction)
        } else {
            needsDisplay = true
        }
    }

    func clearInteractionAction() {
        guard interactionAction != nil else { return }
        interactionAction = nil
        interactionFlip = false
        transition(to: resolvedAction())
    }

    func interactionPropImage(for mode: PetInteractionMode) -> NSImage? {
        spriteSheet.accessoryImage(mode == .wand ? .wand : .treat)
    }

    private func advanceAnimation(at now: TimeInterval) {
        let elapsed = min(max(0, now - (lastTickTime ?? now)), 0.12)
        lastTickTime = now

        if let deadline = temporaryDeadline, Date() >= deadline {
            temporaryAction = nil
            temporaryDeadline = nil
            transition(to: resolvedAction())
        } else {
            let desiredAction = resolvedAction()
            if desiredAction != action {
                transition(to: desiredAction)
            }
        }

        if previousAction != nil {
            transitionElapsed += elapsed
            if transitionElapsed >= transitionDuration {
                previousAction = nil
                transitionElapsed = transitionDuration
            }
            needsDisplay = true
            return
        }

        guard let clip = skin.clip(for: action) else { return }
        frameElapsed += elapsed
        var didAdvanceFrame = false
        while frameElapsed >= clip.frameDuration {
            frameElapsed -= clip.frameDuration
            advanceFrame(clip: clip)
            didAdvanceFrame = true
        }

        if didAdvanceFrame {
            needsDisplay = true
        }
    }

    private func advanceFrame(clip: PetAnimationClip) {
        let nextFrame = frameIndex + 1
        guard nextFrame >= clip.frames else {
            frameIndex = nextFrame
            return
        }

        completedLoops += 1
        if shouldCarousel,
           interactionAction == nil,
           temporaryAction == nil,
           completedLoops >= clip.carouselLoops,
           !skin.restCarouselActions.isEmpty {
            let outgoingFrame = frameIndex
            carouselIndex = (carouselIndex + 1) % skin.restCarouselActions.count
            transition(to: skin.restCarouselActions[carouselIndex], previousFrame: outgoingFrame)
            return
        }

        frameIndex = 0
    }

    private func resetAnimation() {
        carouselIndex = 0
        temporaryAction = nil
        temporaryDeadline = nil
        transition(to: resolvedAction(), resetIfSame: true)
    }

    private func transition(to newAction: PetActionID, previousFrame: Int? = nil, resetIfSame: Bool = false) {
        guard skin.supports(newAction) else { return }

        if newAction == action {
            guard resetIfSame else { return }
            frameIndex = 0
            frameElapsed = 0
            completedLoops = 0
            previousAction = nil
            needsDisplay = true
            return
        }

        previousAction = action
        previousFrameIndex = previousFrame ?? frameIndex
        previousFlip = currentFlip
        transitionElapsed = 0
        action = newAction
        frameIndex = 0
        frameElapsed = 0
        completedLoops = 0
        needsDisplay = true
    }

    private var shouldCarousel: Bool {
        displayMode == .carousel || (displayMode == .automatic && activityPhase == .resting)
    }

    private var currentFlip: Bool {
        interactionAction == action ? interactionFlip : false
    }

    private func resolvedAction() -> PetActionID {
        if let interactionAction {
            return interactionAction
        }
        if let temporaryAction {
            return temporaryAction
        }
        if case .action(let fixedAction) = displayMode, skin.supports(fixedAction) {
            return fixedAction
        }
        if shouldCarousel, !skin.restCarouselActions.isEmpty {
            return skin.restCarouselActions[carouselIndex % skin.restCarouselActions.count]
        }

        switch activityPhase {
        case .working:
            return skin.workingAction
        case .resting:
            return skin.restCarouselActions.first ?? skin.pausedAction
        case .paused:
            return skin.pausedAction
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let clip = skin.clip(for: action) else {
            NSColor.systemGray.withAlphaComponent(0.22).setFill()
            bounds.fill()
            return
        }

        if let previousAction, let previousClip = skin.clip(for: previousAction) {
            let linearProgress = min(max(transitionElapsed / transitionDuration, 0), 1)
            let easedProgress = linearProgress * linearProgress * (3 - 2 * linearProgress)
            spriteSheet.draw(clip: previousClip, frame: previousFrameIndex, in: bounds, fraction: 1 - easedProgress, flippedHorizontally: previousFlip)
            spriteSheet.draw(clip: clip, frame: frameIndex, in: bounds, fraction: easedProgress, flippedHorizontally: currentFlip)
        } else {
            spriteSheet.draw(clip: clip, frame: frameIndex, in: bounds, flippedHorizontally: currentFlip)
        }

        if action == .chasing, interactionAction == nil {
            spriteSheet.drawButterfly(frame: frameIndex, in: bounds)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func mouseDown(with event: NSEvent) {
        onDragStarted?()
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
