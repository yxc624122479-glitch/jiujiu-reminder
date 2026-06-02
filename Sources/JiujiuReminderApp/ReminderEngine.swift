import Foundation

@MainActor
protocol ReminderEngineDelegate: AnyObject {
    func reminderEngineDidChangeState(_ state: ReminderEngine.CycleState, isPaused: Bool)
    func reminderEngineDidStartRest(until deadline: Date)
    func reminderEngineDidTriggerWater()
}

@MainActor
final class ReminderEngine {
    enum CycleState {
        case working
        case resting
    }

    weak var delegate: ReminderEngineDelegate?

    private(set) var settings: ReminderSettings
    private(set) var isPaused = false
    private(set) var state: CycleState = .working

    private var timer: Timer?
    private var workDeadline: Date?
    private var restDeadline: Date?
    private var waterDeadline: Date?
    private var pausedWorkRemaining: TimeInterval?
    private var pausedRestRemaining: TimeInterval?
    private var pausedWaterRemaining: TimeInterval?

    init(settings: ReminderSettings) {
        self.settings = settings
    }

    func updateSettings(_ newSettings: ReminderSettings) {
        settings = newSettings
        resetWorkCycle(resetWater: true)
    }

    func start() {
        guard timer == nil else {
            isPaused = false
            return
        }

        isPaused = false
        state = .working
        workDeadline = Date().addingTimeInterval(minutes(settings.workMinutes))
        waterDeadline = Date().addingTimeInterval(minutes(settings.waterIntervalMinutes))
        startTimer()
        delegate?.reminderEngineDidChangeState(state, isPaused: isPaused)
    }

    func pause() {
        guard !isPaused else { return }

        let now = Date()
        isPaused = true
        pausedWorkRemaining = workDeadline.map { max(0, $0.timeIntervalSince(now)) }
        pausedRestRemaining = restDeadline.map { max(0, $0.timeIntervalSince(now)) }
        pausedWaterRemaining = waterDeadline.map { max(0, $0.timeIntervalSince(now)) }
        timer?.invalidate()
        timer = nil
        delegate?.reminderEngineDidChangeState(state, isPaused: isPaused)
    }

    func resume() {
        guard isPaused else { return }

        let now = Date()
        isPaused = false
        if let remaining = pausedWorkRemaining {
            workDeadline = now.addingTimeInterval(remaining)
        }
        if let remaining = pausedRestRemaining {
            restDeadline = now.addingTimeInterval(remaining)
        }
        if let remaining = pausedWaterRemaining {
            waterDeadline = now.addingTimeInterval(remaining)
        }
        pausedWorkRemaining = nil
        pausedRestRemaining = nil
        pausedWaterRemaining = nil
        startTimer()
        delegate?.reminderEngineDidChangeState(state, isPaused: isPaused)
    }

    func togglePause() {
        isPaused ? resume() : pause()
    }

    func resetWorkCycle(resetWater: Bool = false) {
        state = .working
        workDeadline = Date().addingTimeInterval(minutes(settings.workMinutes))
        restDeadline = nil
        pausedWorkRemaining = nil
        pausedRestRemaining = nil

        if resetWater {
            waterDeadline = Date().addingTimeInterval(minutes(settings.waterIntervalMinutes))
            pausedWaterRemaining = nil
        }

        if !isPaused {
            startTimer()
        }
        delegate?.reminderEngineDidChangeState(state, isPaused: isPaused)
    }

    func completeRest() {
        state = .working
        restDeadline = nil
        workDeadline = Date().addingTimeInterval(minutes(settings.workMinutes))
        startTimer()
        delegate?.reminderEngineDidChangeState(state, isPaused: isPaused)
    }

    func completeWater() {
        waterDeadline = Date().addingTimeInterval(minutes(settings.waterIntervalMinutes))
        startTimer()
    }

    func snoozeWater() {
        waterDeadline = Date().addingTimeInterval(minutes(settings.snoozeMinutes))
        startTimer()
    }

    func statusText() -> String {
        if isPaused {
            return "已暂停"
        }

        let now = Date()
        switch state {
        case .working:
            return "工作中，剩余 \(formatRemaining(workDeadline?.timeIntervalSince(now)))"
        case .resting:
            return "休息中，剩余 \(formatRemaining(restDeadline?.timeIntervalSince(now)))"
        }
    }

    private func startTimer() {
        guard timer == nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick() {
        guard !isPaused else { return }

        let now = Date()
        if state == .working, let deadline = workDeadline, now >= deadline {
            startRest()
        }

        if let deadline = waterDeadline, now >= deadline {
            waterDeadline = nil
            delegate?.reminderEngineDidTriggerWater()
        }
    }

    private func startRest() {
        state = .resting
        workDeadline = nil
        let deadline = Date().addingTimeInterval(minutes(settings.restMinutes))
        restDeadline = deadline
        delegate?.reminderEngineDidChangeState(state, isPaused: isPaused)
        delegate?.reminderEngineDidStartRest(until: deadline)
    }

    private func minutes(_ value: Int) -> TimeInterval {
        TimeInterval(value * 60)
    }

    private func formatRemaining(_ interval: TimeInterval?) -> String {
        let totalSeconds = max(0, Int(interval ?? 0))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
