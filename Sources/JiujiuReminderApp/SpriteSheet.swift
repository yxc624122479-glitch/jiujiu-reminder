import AppKit

final class SpriteSheet {
    let skin: PetSkinDefinition

    private let images: [PetAssetResource: NSImage]
    private let accessoryImages: [PetAccessoryKind: NSImage]

    init?(skin: PetSkinDefinition) {
        var loadedImages: [PetAssetResource: NSImage] = [:]
        for resource in Set(skin.clips.map(\.resource)) {
            guard let image = Self.loadImage(resource) else {
                return nil
            }
            loadedImages[resource] = image
        }

        var loadedAccessories: [PetAccessoryKind: NSImage] = [:]
        for kind in [PetAccessoryKind.butterfly, .wand, .treat] {
            guard let resource = skin.accessory(kind) else { continue }
            guard let image = Self.loadImage(resource) else {
                return nil
            }
            loadedAccessories[kind] = image
        }

        self.skin = skin
        images = loadedImages
        accessoryImages = loadedAccessories
    }

    func draw(
        clip: PetAnimationClip,
        frame: Int,
        in rect: NSRect,
        fraction: CGFloat = 1.0,
        flippedHorizontally: Bool = false
    ) {
        guard let image = images[clip.resource] else { return }

        let frameIndex = frame % clip.frames
        let source = NSRect(
            x: CGFloat(frameIndex) * skin.cellSize.width,
            y: image.size.height - CGFloat(clip.row + 1) * skin.cellSize.height,
            width: skin.cellSize.width,
            height: skin.cellSize.height
        )

        NSGraphicsContext.saveGraphicsState()
        if flippedHorizontally && clip.canMirrorHorizontally {
            let transform = NSAffineTransform()
            transform.translateX(by: rect.minX + rect.maxX, yBy: 0)
            transform.scaleX(by: -1, yBy: 1)
            transform.concat()
        }

        image.draw(
            in: rect,
            from: source,
            operation: .sourceOver,
            fraction: fraction,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    func drawButterfly(frame: Int, in bounds: NSRect, fraction: CGFloat = 1.0) {
        guard let image = accessoryImages[.butterfly] else { return }

        let phase = CGFloat(frame % 12) / 12.0 * .pi * 2
        let size = min(bounds.width, bounds.height) * 0.18
        let center = NSPoint(
            x: bounds.midX + cos(phase) * bounds.width * 0.28,
            y: bounds.minY + bounds.height * 0.20 + sin(phase * 2) * bounds.height * 0.10
        )
        let rect = NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: fraction, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }

    func accessoryImage(_ kind: PetAccessoryKind) -> NSImage? {
        accessoryImages[kind]
    }

    static func resourcesExist(for skin: PetSkinDefinition) -> Bool {
        let resources = Set(skin.clips.map(\.resource) + skin.accessories.values)
        return resources.allSatisfy { findResource($0) != nil }
    }

    private static func loadImage(_ resource: PetAssetResource) -> NSImage? {
        guard let url = findResource(resource) else { return nil }
        return NSImage(contentsOf: url)
    }

    private static func findResource(_ resource: PetAssetResource) -> URL? {
        if let bundled = Bundle.main.url(
            forResource: resource.name,
            withExtension: resource.fileExtension,
            subdirectory: resource.directory
        ) {
            return bundled
        }

        var cwdResource = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources")
        if let directory = resource.directory {
            cwdResource.appendPathComponent(directory)
        }
        cwdResource.appendPathComponent("\(resource.name).\(resource.fileExtension)")
        if FileManager.default.fileExists(atPath: cwdResource.path) {
            return cwdResource
        }

        var executableRelative = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
        if let directory = resource.directory {
            executableRelative.appendPathComponent(directory)
        }
        executableRelative.appendPathComponent("\(resource.name).\(resource.fileExtension)")
        return FileManager.default.fileExists(atPath: executableRelative.path) ? executableRelative : nil
    }
}
