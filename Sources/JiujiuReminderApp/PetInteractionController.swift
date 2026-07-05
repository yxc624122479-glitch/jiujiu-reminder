import AppKit

enum PetInteractionMode {
    case wand
    case treat

    var title: String {
        switch self {
        case .wand: return "逗猫棒"
        case .treat: return "投喂猫条"
        }
    }
}

@MainActor
protocol PetInteractionSessionDelegate: AnyObject {
    func petInteractionDidRequestAction(_ action: PetActionID, flippedHorizontally: Bool)
    func petInteractionDidClearAction()
}

@MainActor
final class PetInteractionSession {
    weak var delegate: PetInteractionSessionDelegate?

    private weak var petWindow: NSWindow?
    private let mode: PetInteractionMode
    private let anchorOrigin: NSPoint
    private let visibleFrame: NSRect
    private let chaseAction: PetActionID
    private let observeAction: PetActionID
    private let treatAction: PetActionID
    private let propWindow: PetPropWindowController
    private var timer: Timer?
    private var deadline = Date().addingTimeInterval(30)
    private var feedingDeadline: Date?
    private var velocity = CGVector.zero
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var wasLeftButtonDown = false
    private(set) var isActive = true

    init(
        mode: PetInteractionMode,
        petWindow: NSWindow,
        anchorOrigin: NSPoint,
        visibleFrame: NSRect,
        chaseAction: PetActionID,
        observeAction: PetActionID,
        treatAction: PetActionID,
        propImage: NSImage
    ) {
        self.mode = mode
        self.petWindow = petWindow
        self.anchorOrigin = anchorOrigin
        self.visibleFrame = visibleFrame
        self.chaseAction = chaseAction
        self.observeAction = observeAction
        self.treatAction = treatAction
        propWindow = PetPropWindowController(image: propImage)
    }

    func start() {
        guard timer == nil else { return }
        deadline = Date().addingTimeInterval(30)
        lastTick = ProcessInfo.processInfo.systemUptime
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        timer?.tolerance = 1.0 / 120.0
        RunLoop.main.add(timer!, forMode: .common)
        tick()
    }

    func stop(animated: Bool) {
        guard isActive else { return }
        isActive = false
        timer?.invalidate()
        timer = nil
        propWindow.hide()
        delegate?.petInteractionDidClearAction()

        guard let petWindow else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.60
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                petWindow.animator().setFrameOrigin(anchorOrigin)
            }
        } else {
            petWindow.setFrameOrigin(anchorOrigin)
        }
    }

    private func tick() {
        guard isActive, let petWindow else {
            stop(animated: false)
            return
        }

        let now = Date()
        if let feedingDeadline {
            let mouthPoint = NSPoint(x: petWindow.frame.midX, y: petWindow.frame.midY + petWindow.frame.height * 0.12)
            propWindow.show(centeredAt: mouthPoint, visibleFrame: visibleFrame)
            delegate?.petInteractionDidRequestAction(treatAction, flippedHorizontally: false)
            if now >= feedingDeadline {
                stop(animated: true)
            }
            return
        }

        if now >= deadline {
            stop(animated: true)
            return
        }

        let uptime = ProcessInfo.processInfo.systemUptime
        let delta = min(max(uptime - lastTick, 0), 0.05)
        lastTick = uptime

        let cursor = clampedCursor(NSEvent.mouseLocation)
        propWindow.show(centeredAt: cursor, visibleFrame: visibleFrame)

        let frame = petWindow.frame
        let petCenter = NSPoint(x: frame.midX, y: frame.midY)
        let targetCenter = NSPoint(x: cursor.x, y: cursor.y - frame.height * 0.34)
        let dx = targetCenter.x - petCenter.x
        let dy = targetCenter.y - petCenter.y
        let distance = hypot(dx, dy)
        let stopRadius: CGFloat = mode == .wand ? 88 : 78
        let flipped = dx < 0

        if distance > stopRadius {
            let maxSpeed: CGFloat = 420
            let desiredSpeed = min(maxSpeed, max(80, distance * 2.2))
            let desiredVelocity = CGVector(
                dx: dx / distance * desiredSpeed,
                dy: dy / distance * desiredSpeed
            )
            let blend = min(1, CGFloat(delta) * 5.0)
            velocity.dx += (desiredVelocity.dx - velocity.dx) * blend
            velocity.dy += (desiredVelocity.dy - velocity.dy) * blend

            let proposedOrigin = NSPoint(
                x: frame.origin.x + velocity.dx * CGFloat(delta),
                y: frame.origin.y + velocity.dy * CGFloat(delta)
            )
            petWindow.setFrameOrigin(clampedPetOrigin(proposedOrigin, size: frame.size))
            delegate?.petInteractionDidRequestAction(chaseAction, flippedHorizontally: flipped)
        } else {
            velocity.dx *= 0.72
            velocity.dy *= 0.72
            delegate?.petInteractionDidRequestAction(mode == .wand ? chaseAction : observeAction, flippedHorizontally: flipped)
        }

        if mode == .treat {
            let isLeftButtonDown = (NSEvent.pressedMouseButtons & 1) == 1
            if distance <= 105, isLeftButtonDown, !wasLeftButtonDown {
                feedingDeadline = now.addingTimeInterval(3.60)
                velocity = .zero
            }
            wasLeftButtonDown = isLeftButtonDown
        }
    }

    private func clampedCursor(_ point: NSPoint) -> NSPoint {
        let inset: CGFloat = 28
        return NSPoint(
            x: min(max(point.x, visibleFrame.minX + inset), visibleFrame.maxX - inset),
            y: min(max(point.y, visibleFrame.minY + inset), visibleFrame.maxY - inset)
        )
    }

    private func clampedPetOrigin(_ origin: NSPoint, size: NSSize) -> NSPoint {
        NSPoint(
            x: min(max(origin.x, visibleFrame.minX), max(visibleFrame.minX, visibleFrame.maxX - size.width)),
            y: min(max(origin.y, visibleFrame.minY), max(visibleFrame.minY, visibleFrame.maxY - size.height))
        )
    }
}

@MainActor
private final class PetPropWindowController: NSWindowController {
    private let propView: PetPropView

    init(image: NSImage) {
        propView = PetPropView(image: image)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 74, height: 74),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = propView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(centeredAt point: NSPoint, visibleFrame: NSRect) {
        guard let window else { return }
        let origin = NSPoint(
            x: min(max(point.x - window.frame.width / 2, visibleFrame.minX), visibleFrame.maxX - window.frame.width),
            y: min(max(point.y - window.frame.height / 2, visibleFrame.minY), visibleFrame.maxY - window.frame.height)
        )
        window.setFrameOrigin(origin)
        window.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }
}

@MainActor
private final class PetPropView: NSView {
    private let image: NSImage

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        image.draw(in: bounds.insetBy(dx: 4, dy: 4), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }
}
