import AppKit

enum PetActivityPhase {
    case working
    case resting
    case paused
}

enum PetAnimationState {
    case idle
    case runningRight
    case runningLeft
    case waving
    case jumping
    case failed
    case waiting
    case working
    case review

    var row: Int {
        switch self {
        case .idle: return 0
        case .runningRight: return 1
        case .runningLeft: return 2
        case .waving: return 3
        case .jumping: return 4
        case .failed: return 5
        case .waiting: return 6
        case .working: return 7
        case .review: return 8
        }
    }

    var frames: Int {
        switch self {
        case .idle: return 6
        case .runningRight: return 8
        case .runningLeft: return 8
        case .waving: return 4
        case .jumping: return 5
        case .failed: return 8
        case .waiting: return 6
        case .working: return 6
        case .review: return 6
        }
    }
}

enum PetDisplayMode: String, CaseIterable {
    case automatic
    case working
    case restCarousel
    case idle
    case runningRight
    case runningLeft
    case waving
    case jumping
    case waiting
    case review
    case failed

    var title: String {
        switch self {
        case .automatic: return "自动跟随"
        case .working: return "工作中"
        case .restCarousel: return "休息轮播"
        case .idle: return "发呆"
        case .runningRight: return "向右奔跑"
        case .runningLeft: return "向左奔跑"
        case .waving: return "打招呼"
        case .jumping: return "跳跃"
        case .waiting: return "等待"
        case .review: return "完成"
        case .failed: return "不开心"
        }
    }

    var fixedState: PetAnimationState? {
        switch self {
        case .automatic, .restCarousel:
            return nil
        case .working:
            return .working
        case .idle:
            return .idle
        case .runningRight:
            return .runningRight
        case .runningLeft:
            return .runningLeft
        case .waving:
            return .waving
        case .jumping:
            return .jumping
        case .waiting:
            return .waiting
        case .review:
            return .review
        case .failed:
            return .failed
        }
    }

    static let restCarouselStates: [PetAnimationState] = [
        .idle,
        .runningRight,
        .runningLeft,
        .waving,
        .jumping,
        .waiting,
        .review
    ]
}

final class SpriteSheet {
    static let cellSize = NSSize(width: 192, height: 208)

    private let image: NSImage
    private let columns = 8

    init?(resourceName: String = "spritesheet") {
        guard let url = Self.findResource(named: resourceName),
              let loaded = NSImage(contentsOf: url) else {
            return nil
        }

        image = loaded
    }

    func draw(state: PetAnimationState, frame: Int, in rect: NSRect) {
        let frameIndex = frame % state.frames
        let source = NSRect(
            x: CGFloat(frameIndex) * Self.cellSize.width,
            y: image.size.height - CGFloat(state.row + 1) * Self.cellSize.height,
            width: Self.cellSize.width,
            height: Self.cellSize.height
        )
        image.draw(in: rect, from: source, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }

    private static func findResource(named name: String) -> URL? {
        if let bundled = Bundle.main.url(forResource: name, withExtension: "png") {
            return bundled
        }

        let cwdResource = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources")
            .appendingPathComponent("\(name).png")
        if FileManager.default.fileExists(atPath: cwdResource.path) {
            return cwdResource
        }

        let executableRelative = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
            .appendingPathComponent("\(name).png")
        if FileManager.default.fileExists(atPath: executableRelative.path) {
            return executableRelative
        }

        return nil
    }
}
