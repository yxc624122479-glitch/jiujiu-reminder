import AppKit

struct ReminderSettings {
    var workMinutes: Int
    var restMinutes: Int
    var waterIntervalMinutes: Int
    var snoozeMinutes: Int
    var hasCompletedFirstRun: Bool
    var launchAtLoginEnabled: Bool
    var petDisplayMode: PetDisplayMode
    var petSkinID: PetSkinID
    var petScale: CGFloat
    var petPosition: NSPoint?

    static let defaults = ReminderSettings(
        workMinutes: 25,
        restMinutes: 5,
        waterIntervalMinutes: 30,
        snoozeMinutes: 5,
        hasCompletedFirstRun: false,
        launchAtLoginEnabled: false,
        petDisplayMode: .automatic,
        petSkinID: .classic,
        petScale: PetSizePreset.standard.scale,
        petPosition: nil
    )
}

final class SettingsStore {
    private enum Key {
        static let workMinutes = "workMinutes"
        static let restMinutes = "restMinutes"
        static let waterIntervalMinutes = "waterIntervalMinutes"
        static let snoozeMinutes = "snoozeMinutes"
        static let hasCompletedFirstRun = "hasCompletedFirstRun"
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
        static let petDisplayMode = "petDisplayMode"
        static let petSkinID = "petSkinID"
        static let petScale = "petScale"
        static let petPositionX = "petPositionX"
        static let petPositionY = "petPositionY"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ReminderSettings {
        let base = ReminderSettings.defaults
        let hasPosition = defaults.object(forKey: Key.petPositionX) != nil && defaults.object(forKey: Key.petPositionY) != nil
        let position = hasPosition
            ? NSPoint(x: defaults.double(forKey: Key.petPositionX), y: defaults.double(forKey: Key.petPositionY))
            : nil

        return ReminderSettings(
            workMinutes: positiveInt(forKey: Key.workMinutes, fallback: base.workMinutes),
            restMinutes: positiveInt(forKey: Key.restMinutes, fallback: base.restMinutes),
            waterIntervalMinutes: positiveInt(forKey: Key.waterIntervalMinutes, fallback: base.waterIntervalMinutes),
            snoozeMinutes: positiveInt(forKey: Key.snoozeMinutes, fallback: base.snoozeMinutes),
            hasCompletedFirstRun: defaults.bool(forKey: Key.hasCompletedFirstRun),
            launchAtLoginEnabled: defaults.bool(forKey: Key.launchAtLoginEnabled),
            petDisplayMode: PetDisplayMode(persistedValue: defaults.string(forKey: Key.petDisplayMode) ?? base.petDisplayMode.persistedValue),
            petSkinID: PetSkinID(rawValue: defaults.string(forKey: Key.petSkinID) ?? "") ?? base.petSkinID,
            petScale: petScale(fallback: base.petScale),
            petPosition: position
        )
    }

    func save(_ settings: ReminderSettings) {
        defaults.set(settings.workMinutes, forKey: Key.workMinutes)
        defaults.set(settings.restMinutes, forKey: Key.restMinutes)
        defaults.set(settings.waterIntervalMinutes, forKey: Key.waterIntervalMinutes)
        defaults.set(settings.snoozeMinutes, forKey: Key.snoozeMinutes)
        defaults.set(settings.hasCompletedFirstRun, forKey: Key.hasCompletedFirstRun)
        defaults.set(settings.launchAtLoginEnabled, forKey: Key.launchAtLoginEnabled)
        defaults.set(settings.petDisplayMode.persistedValue, forKey: Key.petDisplayMode)
        defaults.set(settings.petSkinID.rawValue, forKey: Key.petSkinID)
        defaults.set(Double(settings.petScale), forKey: Key.petScale)

        if let position = settings.petPosition {
            defaults.set(position.x, forKey: Key.petPositionX)
            defaults.set(position.y, forKey: Key.petPositionY)
        }
    }

    func savePetPosition(_ point: NSPoint) {
        defaults.set(point.x, forKey: Key.petPositionX)
        defaults.set(point.y, forKey: Key.petPositionY)
    }

    func savePetDisplayMode(_ mode: PetDisplayMode) {
        defaults.set(mode.persistedValue, forKey: Key.petDisplayMode)
    }

    func savePetSkinID(_ skinID: PetSkinID) {
        defaults.set(skinID.rawValue, forKey: Key.petSkinID)
    }

    func savePetScale(_ scale: CGFloat) {
        defaults.set(Double(scale), forKey: Key.petScale)
    }

    private func positiveInt(forKey key: String, fallback: Int) -> Int {
        guard defaults.object(forKey: key) != nil else {
            return fallback
        }

        let value = defaults.integer(forKey: key)
        return value > 0 ? value : fallback
    }

    private func petScale(fallback: CGFloat) -> CGFloat {
        guard defaults.object(forKey: Key.petScale) != nil else {
            return fallback
        }

        let value = CGFloat(defaults.double(forKey: Key.petScale))
        return (0.6...1.5).contains(value) ? value : fallback
    }
}
