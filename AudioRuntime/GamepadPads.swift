import GameController
import MusicDomain

/// I55 · Connects any MFi, Xbox or PlayStation controller as drum pads while the app is
/// open. Presses go through the same path as touching a pad, so they record too.
@MainActor final class GamepadPads {
    static let shared = GamepadPads()
    private(set) var connected: String?
    private weak var session: Session?
    private var mapping = GamepadMapping.standard
    private var pressed: Set<GamepadControl> = []
    private var observers: [NSObjectProtocol] = []

    func attach(_ session: Session) {
        self.session = session
        guard observers.isEmpty else { return }
        observers.append(NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { GCController.controllers().forEach { self?.bind($0) } }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.connected = GCController.controllers().first?.vendorName }
        })
        GCController.controllers().forEach(bind)
    }

    private func bind(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        connected = controller.vendorName ?? "Game controller"
        let inputs: [(GamepadControl, GCControllerButtonInput?)] = [
            (.a, pad.buttonA), (.b, pad.buttonB), (.x, pad.buttonX), (.y, pad.buttonY),
            (.leftShoulder, pad.leftShoulder), (.rightShoulder, pad.rightShoulder),
            (.leftTrigger, pad.leftTrigger), (.rightTrigger, pad.rightTrigger),
            (.up, pad.dpad.up), (.down, pad.dpad.down), (.left, pad.dpad.left), (.right, pad.dpad.right),
            (.menu, pad.buttonMenu), (.options, pad.buttonOptions),
        ]
        for (control, input) in inputs {
            input?.valueChangedHandler = { [weak self] _, value, _ in
                Task { @MainActor in self?.handle(control, value: value) }
            }
        }
    }

    private func handle(_ control: GamepadControl, value: Float) {
        let was = pressed.contains(control)
        if let hit = mapping.hit(control, value: value, wasPressed: was) { session?.hit(hit.pad, velocity: hit.velocity) }
        let threshold: Float = control == .leftTrigger || control == .rightTrigger ? 0.15 : 0.5
        if value > threshold { pressed.insert(control) } else { pressed.remove(control) }
    }
}
