import Foundation

enum AutomaticAgentActions {
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
