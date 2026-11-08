import Foundation

enum AutomaticAgentActions {
    /// Run the chosen profile sequence from a direct launcher action. The primary
    /// action must finish successfully before any configured secondary is invoked.
    static func run(afterPrimary open: (@escaping (String?) -> Void) -> Void,
                    actions: [AgentSecondaryAction],
                    isCurrent: @escaping () -> Bool,
                    perform: @escaping (AgentSecondaryAction, @escaping (String?) -> Void) -> Void,
                    completion: @escaping (String?) -> Void) {
        guard isCurrent() else { completion("Action sequence canceled because the configuration changed."); return }
        open { error in
            if let error { completion(error); return }
            guard isCurrent() else { completion("Action sequence canceled because the configuration changed."); return }
            run(actions, perform: { action, next in
                guard isCurrent() else { next("Action sequence canceled because the configuration changed."); return }
                perform(action, next)
            }, completion: completion)
        }
    }

    static func run(_ actions: [AgentSecondaryAction], perform: @escaping (AgentSecondaryAction, @escaping (String?) -> Void) -> Void, completion: @escaping (String?) -> Void) {
        func step(_ index: Int) {
            guard index < actions.count else { completion(nil); return }
            var action = actions[index]
            action.openAgentFirst = false
            perform(action) { error in
                if let error { completion(error) } else { step(index + 1) }
            }
        }
        step(0)
    }
}

/// Main-thread cancellation token shared by pending primary and secondary actions.
final class ActionGeneration {
    private var value: UInt = 0
    func cancel() { value &+= 1 }
    func checkpoint() -> () -> Bool {
        let expected = value
        return { [weak self] in self?.value == expected }
    }
}
