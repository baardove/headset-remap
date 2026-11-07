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
