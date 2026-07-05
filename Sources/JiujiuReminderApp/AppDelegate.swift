import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private var settings = ReminderSettings.defaults
    private var engine: ReminderEngine?
    private var petWindowController: PetWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var activeAlerts: [ReminderAlertWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        settings = settingsStore.load()
        let petWindowController = PetWindowController(
            initialPosition: settings.petPosition,
            scale: settings.petScale,
            skinID: settings.petSkinID
        )
        petWindowController.delegate = self
        self.petWindowController = petWindowController
        if petWindowController.activeSkinID != settings.petSkinID {
            settings.petSkinID = petWindowController.activeSkinID
            settings.petDisplayMode = .automatic
            settingsStore.save(settings)
        } else {
            let normalizedMode = settings.petDisplayMode.normalized(
                for: PetSkinDefinition.definition(for: settings.petSkinID)
            )
            if normalizedMode != settings.petDisplayMode {
                settings.petDisplayMode = normalizedMode
                settingsStore.savePetDisplayMode(normalizedMode)
            }
        }
        petWindowController.setDisplayMode(settings.petDisplayMode)
        petWindowController.show()

        let engine = ReminderEngine(settings: settings)
        engine.delegate = self
        self.engine = engine

        if settings.hasCompletedFirstRun {
            engine.start()
        } else {
            showSettings(isFirstRun: true)
        }
    }

    private func showSettings(isFirstRun: Bool) {
        let controller = SettingsWindowController(settings: settings, isFirstRun: isFirstRun)
        controller.onSave = { [weak self] newSettings in
            guard let self else { return }
            settings = newSettings
            settingsStore.save(newSettings)

            if engine == nil {
                engine = ReminderEngine(settings: newSettings)
                engine?.delegate = self
            } else {
                engine?.updateSettings(newSettings)
            }
            engine?.start()
            updatePetActivity()
        }
        controller.onCancelFirstRun = {
            NSApp.terminate(nil)
        }
        settingsWindowController = controller
        controller.show()
    }

    private func showMessage(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "知道了")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func keepAlert(_ controller: ReminderAlertWindowController) {
        activeAlerts.append(controller)
    }

    private func releaseAlert(_ controller: ReminderAlertWindowController) {
        activeAlerts.removeAll { $0 === controller }
    }
}

extension AppDelegate: PetWindowControllerDelegate {
    func petWindowDidRequestTogglePause() {
        engine?.togglePause()
    }

    func petWindowDidRequestResetCycle() {
        engine?.resetWorkCycle(resetWater: false)
        petWindowController?.pulse()
    }

    func petWindowDidRequestSettings() {
        showSettings(isFirstRun: false)
    }

    func petWindowDidRequestLaunchAtLoginToggle() {
        let nextValue = !settings.launchAtLoginEnabled
        do {
            try LaunchAtLoginManager.setEnabled(nextValue)
            settings.launchAtLoginEnabled = nextValue
            settingsStore.save(settings)
        } catch {
            LaunchAtLoginManager.openLoginItemsSettings()
            showMessage(
                title: "无法自动修改开机启动",
                message: "当前打包方式或系统权限不允许直接写入登录项。我已经打开系统登录项设置，你可以在那里手动添加玖玖提醒。"
            )
        }
    }

    func petWindowDidRequestDisplayMode(_ mode: PetDisplayMode) {
        let normalizedMode = mode.normalized(for: PetSkinDefinition.definition(for: settings.petSkinID))
        settings.petDisplayMode = normalizedMode
        settingsStore.savePetDisplayMode(normalizedMode)
        petWindowController?.setDisplayMode(normalizedMode)
    }

    func petWindowDidRequestSkin(_ skinID: PetSkinID) {
        guard skinID != settings.petSkinID else { return }
        guard let normalizedMode = petWindowController?.setSkin(
            skinID,
            displayMode: settings.petDisplayMode,
            scale: settings.petScale
        ) else {
            showMessage(
                title: "无法切换桌宠皮肤",
                message: "“\(skinID.title)”的动画资源不完整，已保留当前皮肤。"
            )
            return
        }

        settings.petSkinID = skinID
        settings.petDisplayMode = normalizedMode
        settingsStore.save(settings)
    }

    func petWindowDidRequestScale(_ scale: CGFloat) {
        settings.petScale = scale
        settingsStore.savePetScale(scale)
        petWindowController?.setScale(scale)
    }

    func petWindowDidRequestQuit() {
        NSApp.terminate(nil)
    }

    func petWindowStatusText() -> String {
        engine?.statusText() ?? "准备中"
    }

    func petWindowIsPaused() -> Bool {
        engine?.isPaused ?? false
    }

    func petWindowLaunchAtLoginEnabled() -> Bool {
        settings.launchAtLoginEnabled
    }

    func petWindowDisplayMode() -> PetDisplayMode {
        settings.petDisplayMode
    }

    func petWindowSkinID() -> PetSkinID {
        settings.petSkinID
    }

    func petWindowScale() -> CGFloat {
        settings.petScale
    }

    func petWindowDidMove(to point: NSPoint) {
        settings.petPosition = point
        settingsStore.savePetPosition(point)
    }
}

extension AppDelegate: ReminderEngineDelegate {
    func reminderEngineDidChangeState(_ state: ReminderEngine.CycleState, isPaused: Bool) {
        updatePetActivity()
    }

    func reminderEngineDidStartRest(until deadline: Date) {
        petWindowController?.pulse(.rest)

        let controller = ReminderAlertWindowController(
            title: "该起来活动一下了",
            message: "先离开屏幕，伸展一下肩颈和腿。倒计时结束后再回来点完成。"
        )
        keepAlert(controller)
        controller.configureRest(deadline: deadline) { [weak self, weak controller] in
            self?.engine?.completeRest()
            if let controller {
                self?.releaseAlert(controller)
            }
        }
        controller.show()
    }

    func reminderEngineDidTriggerWater() {
        petWindowController?.pulse(.water)

        let controller = ReminderAlertWindowController(
            title: "该喝水了",
            message: "喝点水，再继续工作。"
        )
        keepAlert(controller)
        controller.configureWater(
            snoozeMinutes: settings.snoozeMinutes,
            onDone: { [weak self, weak controller] in
                self?.engine?.completeWater()
                if let controller {
                    self?.releaseAlert(controller)
                }
            },
            onSnooze: { [weak self, weak controller] in
                self?.engine?.snoozeWater()
                if let controller {
                    self?.releaseAlert(controller)
                }
            }
        )
        controller.show()
    }
}

private extension AppDelegate {
    func updatePetActivity() {
        guard let engine else {
            petWindowController?.setActivityPhase(.paused)
            return
        }

        if engine.isPaused {
            petWindowController?.setActivityPhase(.paused)
            return
        }

        switch engine.state {
        case .working:
            petWindowController?.setActivityPhase(.working)
        case .resting:
            petWindowController?.setActivityPhase(.resting)
        }
    }
}
