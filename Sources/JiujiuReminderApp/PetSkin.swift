import AppKit

struct PetActionID: RawRepresentable, Hashable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let idle = PetActionID(rawValue: "idle")
    static let runningRight = PetActionID(rawValue: "running-right")
    static let runningLeft = PetActionID(rawValue: "running-left")
    static let waving = PetActionID(rawValue: "waving")
    static let jumping = PetActionID(rawValue: "jumping")
    static let failed = PetActionID(rawValue: "failed")
    static let waiting = PetActionID(rawValue: "waiting")
    static let working = PetActionID(rawValue: "working")
    static let review = PetActionID(rawValue: "review")

    static let eating = PetActionID(rawValue: "eating")
    static let drinking = PetActionID(rawValue: "drinking")
    static let rolling = PetActionID(rawValue: "rolling")
    static let grooming = PetActionID(rawValue: "grooming")
    static let chasing = PetActionID(rawValue: "chasing")
    static let sleeping = PetActionID(rawValue: "sleeping")
    static let stretching = PetActionID(rawValue: "stretching")
    static let observing = PetActionID(rawValue: "observing")
    static let treat = PetActionID(rawValue: "treat")
}

struct PetAssetResource: Hashable {
    let directory: String?
    let name: String
    let fileExtension: String

    init(directory: String? = nil, name: String, fileExtension: String = "png") {
        self.directory = directory
        self.name = name
        self.fileExtension = fileExtension
    }
}

struct PetAnimationClip {
    let id: PetActionID
    let title: String
    let resource: PetAssetResource
    let row: Int
    let frames: Int
    let frameDuration: TimeInterval
    let carouselLoops: Int
    let canMirrorHorizontally: Bool
}

enum PetAccessoryKind {
    case butterfly
    case wand
    case treat
}

enum PetSkinID: String, CaseIterable {
    case classic
    case realistic

    var title: String {
        switch self {
        case .classic: return "经典玖玖"
        case .realistic: return "真实玖玖"
        }
    }
}

enum PetSizePreset: String, CaseIterable {
    case compact
    case small
    case standard
    case large
    case extraLarge

    var title: String {
        switch self {
        case .compact: return "迷你（60%）"
        case .small: return "小（80%）"
        case .standard: return "标准（100%）"
        case .large: return "大（125%）"
        case .extraLarge: return "超大（150%）"
        }
    }

    var scale: CGFloat {
        switch self {
        case .compact: return 0.6
        case .small: return 0.8
        case .standard: return 1.0
        case .large: return 1.25
        case .extraLarge: return 1.5
        }
    }

    static func closest(to scale: CGFloat) -> PetSizePreset {
        allCases.min { abs($0.scale - scale) < abs($1.scale - scale) } ?? .standard
    }
}

enum PetReminderCue {
    case generic
    case rest
    case water
}

struct PetSkinDefinition {
    let id: PetSkinID
    let cellSize: NSSize
    let displaySize: NSSize
    let columns: Int
    let clips: [PetAnimationClip]
    let manualActions: [PetActionID]
    let workingAction: PetActionID
    let pausedAction: PetActionID
    let restCarouselActions: [PetActionID]
    let genericCueAction: PetActionID
    let restCueAction: PetActionID
    let waterCueAction: PetActionID
    let chaseInteractionAction: PetActionID?
    let treatInteractionAction: PetActionID?
    let accessories: [PetAccessoryKind: PetAssetResource]

    var displayName: String { id.title }

    func clip(for action: PetActionID) -> PetAnimationClip? {
        clips.first { $0.id == action }
    }

    func supports(_ action: PetActionID) -> Bool {
        clip(for: action) != nil
    }

    func cueAction(for cue: PetReminderCue) -> PetActionID {
        switch cue {
        case .generic: return genericCueAction
        case .rest: return restCueAction
        case .water: return waterCueAction
        }
    }

    func accessory(_ kind: PetAccessoryKind) -> PetAssetResource? {
        accessories[kind]
    }

    static func definition(for id: PetSkinID) -> PetSkinDefinition {
        switch id {
        case .classic:
            return classic
        case .realistic:
            return realistic
        }
    }

    static let classic: PetSkinDefinition = {
        let atlas = PetAssetResource(name: "spritesheet")
        let clips = [
            PetAnimationClip(id: .idle, title: "发呆", resource: atlas, row: 0, frames: 6, frameDuration: 0.22, carouselLoops: 2, canMirrorHorizontally: false),
            PetAnimationClip(id: .runningRight, title: "向右奔跑", resource: atlas, row: 1, frames: 8, frameDuration: 0.11, carouselLoops: 2, canMirrorHorizontally: false),
            PetAnimationClip(id: .runningLeft, title: "向左奔跑", resource: atlas, row: 2, frames: 8, frameDuration: 0.11, carouselLoops: 2, canMirrorHorizontally: false),
            PetAnimationClip(id: .waving, title: "打招呼", resource: atlas, row: 3, frames: 4, frameDuration: 0.16, carouselLoops: 3, canMirrorHorizontally: false),
            PetAnimationClip(id: .jumping, title: "跳跃", resource: atlas, row: 4, frames: 5, frameDuration: 0.12, carouselLoops: 2, canMirrorHorizontally: false),
            PetAnimationClip(id: .failed, title: "不开心", resource: atlas, row: 5, frames: 8, frameDuration: 0.18, carouselLoops: 2, canMirrorHorizontally: false),
            PetAnimationClip(id: .waiting, title: "等待", resource: atlas, row: 6, frames: 6, frameDuration: 0.20, carouselLoops: 2, canMirrorHorizontally: false),
            PetAnimationClip(id: .working, title: "工作中", resource: atlas, row: 7, frames: 6, frameDuration: 0.17, carouselLoops: 2, canMirrorHorizontally: false),
            PetAnimationClip(id: .review, title: "完成", resource: atlas, row: 8, frames: 6, frameDuration: 0.18, carouselLoops: 2, canMirrorHorizontally: false)
        ]

        return PetSkinDefinition(
            id: .classic,
            cellSize: NSSize(width: 192, height: 208),
            displaySize: NSSize(width: 192, height: 208),
            columns: 8,
            clips: clips,
            manualActions: [.working, .idle, .runningRight, .runningLeft, .waving, .jumping, .waiting, .review, .failed],
            workingAction: .working,
            pausedAction: .idle,
            restCarouselActions: [.idle, .runningRight, .runningLeft, .waving, .jumping, .waiting, .review],
            genericCueAction: .waving,
            restCueAction: .waving,
            waterCueAction: .waving,
            chaseInteractionAction: nil,
            treatInteractionAction: nil,
            accessories: [:]
        )
    }()

    static let realistic: PetSkinDefinition = {
        let directory = "Skins/realistic"
        let atlas = PetAssetResource(directory: directory, name: "spritesheet-realistic")
        let treatStrip = PetAssetResource(directory: directory, name: "interaction-treat")
        let clips = [
            PetAnimationClip(id: .eating, title: "吃猫粮", resource: atlas, row: 0, frames: 12, frameDuration: 0.18, carouselLoops: 2, canMirrorHorizontally: false),
            PetAnimationClip(id: .drinking, title: "喝水", resource: atlas, row: 1, frames: 12, frameDuration: 0.18, carouselLoops: 2, canMirrorHorizontally: false),
            PetAnimationClip(id: .rolling, title: "翻肚打滚", resource: atlas, row: 2, frames: 12, frameDuration: 0.16, carouselLoops: 2, canMirrorHorizontally: false),
            PetAnimationClip(id: .grooming, title: "舔猫毛", resource: atlas, row: 3, frames: 12, frameDuration: 0.18, carouselLoops: 2, canMirrorHorizontally: false),
            PetAnimationClip(id: .chasing, title: "追蝴蝶", resource: atlas, row: 4, frames: 12, frameDuration: 0.14, carouselLoops: 2, canMirrorHorizontally: true),
            PetAnimationClip(id: .working, title: "工作", resource: atlas, row: 5, frames: 12, frameDuration: 0.20, carouselLoops: 2, canMirrorHorizontally: false),
            PetAnimationClip(id: .sleeping, title: "睡觉", resource: atlas, row: 6, frames: 12, frameDuration: 0.28, carouselLoops: 2, canMirrorHorizontally: false),
            PetAnimationClip(id: .stretching, title: "伸懒腰", resource: atlas, row: 7, frames: 12, frameDuration: 0.18, carouselLoops: 2, canMirrorHorizontally: false),
            PetAnimationClip(id: .observing, title: "坐立观察", resource: atlas, row: 8, frames: 12, frameDuration: 0.22, carouselLoops: 2, canMirrorHorizontally: true),
            PetAnimationClip(id: .treat, title: "吃猫条", resource: treatStrip, row: 0, frames: 12, frameDuration: 0.18, carouselLoops: 2, canMirrorHorizontally: true)
        ]

        return PetSkinDefinition(
            id: .realistic,
            cellSize: NSSize(width: 256, height: 256),
            displaySize: NSSize(width: 208, height: 208),
            columns: 12,
            clips: clips,
            manualActions: [.eating, .drinking, .rolling, .grooming, .chasing, .working, .sleeping, .stretching, .observing],
            workingAction: .working,
            pausedAction: .sleeping,
            restCarouselActions: [.observing, .grooming, .rolling, .stretching, .sleeping, .eating, .drinking, .chasing],
            genericCueAction: .observing,
            restCueAction: .stretching,
            waterCueAction: .drinking,
            chaseInteractionAction: .chasing,
            treatInteractionAction: .treat,
            accessories: [
                .butterfly: PetAssetResource(directory: directory, name: "butterfly"),
                .wand: PetAssetResource(directory: directory, name: "wand-lure"),
                .treat: PetAssetResource(directory: directory, name: "cat-treat")
            ]
        )
    }()
}

enum PetDisplayMode: Equatable {
    case automatic
    case carousel
    case action(PetActionID)

    var persistedValue: String {
        switch self {
        case .automatic:
            return "automatic"
        case .carousel:
            return "carousel"
        case .action(let action):
            return "action:\(action.rawValue)"
        }
    }

    init(persistedValue: String) {
        if persistedValue == "automatic" {
            self = .automatic
            return
        }
        if persistedValue == "carousel" || persistedValue == "restCarousel" {
            self = .carousel
            return
        }
        if persistedValue.hasPrefix("action:") {
            self = .action(PetActionID(rawValue: String(persistedValue.dropFirst("action:".count))))
            return
        }

        let migratedActions: [String: PetActionID] = [
            "working": .working,
            "idle": .idle,
            "runningRight": .runningRight,
            "runningLeft": .runningLeft,
            "waving": .waving,
            "jumping": .jumping,
            "waiting": .waiting,
            "review": .review,
            "failed": .failed
        ]
        self = migratedActions[persistedValue].map(PetDisplayMode.action) ?? .automatic
    }

    func normalized(for skin: PetSkinDefinition) -> PetDisplayMode {
        switch self {
        case .automatic, .carousel:
            return self
        case .action(let action):
            return skin.supports(action) && skin.manualActions.contains(action) ? self : .automatic
        }
    }
}

enum PetActivityPhase {
    case working
    case resting
    case paused
}
