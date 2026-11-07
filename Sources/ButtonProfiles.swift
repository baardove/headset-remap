import Foundation

struct ButtonProfile: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var settings: ButtonSettings
    var activateShortcut: KeyboardShortcut?
    var runShortcut: KeyboardShortcut?
    var secondaryActions: [AgentSecondaryAction]?
    var additionalButtons: [HeadsetButton]?
    var enabled: Bool?
    var builtInSiri: Bool?
    var automaticActionSelection: String?
    var automaticActions: [AgentSecondaryAction] {
        if automaticActionSelection == "none" { return [] }
        if let selection = automaticActionSelection { return (secondaryActions ?? []).filter { $0.id.uuidString == selection && $0.isConfigured } }
        return (secondaryActions ?? []).filter { $0.isConfigured && $0.runAfterHeadset != false }
    }
    var isEnabled: Bool { builtInSiri == true || enabled != false }

    init(id: UUID = UUID(), name: String, settings: ButtonSettings) {
        self.id = id; self.name = name; self.settings = settings
    }
}

struct ButtonProfileLibrary: Codable, Equatable {
    static let defaultsKey = "buttonProfiles.v1"
    static let recoveryKey = "buttonProfiles.unreadableBackup"
    private(set) var profiles: [ButtonProfile]
    private(set) var activeID: UUID
    private(set) var agentCatalogVersion: Int?
    private(set) var codexActionPresetsVersion: Int?
    private(set) var cycleShortcuts: AgentCycleShortcuts?
    var effectiveCycleShortcuts: AgentCycleShortcuts { cycleShortcuts ?? .defaults }

    var enabledProfiles: [ButtonProfile] { profiles.filter(\.isEnabled) }
    func number(for id: UUID) -> Int? { enabledProfiles.firstIndex { $0.id == id }.map { $0 + 1 } }
    func displayName(_ profile: ButtonProfile) -> String { number(for: profile.id).map { "\($0). \(profile.name)" } ?? profile.name }
    var active: ButtonProfile { profiles.first { $0.id == activeID }! }

    init(profiles: [ButtonProfile], activeID: UUID) throws {
        self.profiles = profiles; self.activeID = activeID
        try validate()
    }

    enum ProfileError: LocalizedError {
        case empty, missing, duplicateName, invalidName, duplicateID, lastProfile, invalidShortcut, shortcutConflict, buttonConflict, pinnedSiri, disabledAgent, recursiveAction
        var errorDescription: String? {
            switch self {
            case .empty: return "At least one profile is required."
            case .missing: return "The selected profile no longer exists."
            case .duplicateName: return "A profile with that name already exists."
            case .invalidName: return "Use a profile name between 1 and 60 characters."
            case .duplicateID: return "The profile library contains duplicate identifiers."
            case .lastProfile: return "Keep at least one profile."
            case .invalidShortcut: return "Use a key together with Control, Option or Command."
            case .shortcutConflict: return "That keyboard shortcut is already assigned. Choose a different combination."
            case .recursiveAction: return "An agent’s Open action cannot refer to another agent action."
            case .pinnedSiri: return "Siri is fixed as agent 1 and cannot be moved, disabled, renamed or removed."
            case .disabledAgent: return "Configure and enable this agent before using it."
            case .buttonConflict: return "This input is already assigned to another button in this profile. Choose a different press event."
            }
        }
    }

    static func seeded(current: ButtonSettings, currentName: String,
                       alternatives: [(name: String, action: ButtonAction, target: String)] = []) -> Self {
        let first = ButtonProfile(name: currentName, settings: current)
        var profiles = [first]
        for preset in alternatives {
            guard !profiles.contains(where: { normalized($0.name) == normalized(preset.name) }) else { continue }
            var settings = current
            settings.action = preset.action; settings.target = preset.target
            profiles.append(ButtonProfile(name: preset.name, settings: settings))
        }
        // All names above come from the app's known preset labels.
        return try! Self(profiles: profiles, activeID: first.id)
    }

    @discardableResult
    mutating func migrateGrokWebProfile(to applicationPath: String) -> Bool {
        var changed = false
        for index in profiles.indices {
            let profile = profiles[index]
            guard Self.normalized(profile.name) == "grok", profile.settings.action == .openURL,
                  ["https://grok.com", "https://grok.com/"].contains(profile.settings.target) else { continue }
            profiles[index].settings.action = .openApp
            profiles[index].settings.target = applicationPath
            changed = true
        }
        return changed
    }

    var hotkeys: [ProfileHotkey] {
        var keys = enabledProfiles.flatMap { profile in
            [profile.activateShortcut.map { ProfileHotkey(profileID: profile.id, purpose: .activate, shortcut: $0) },
             profile.runShortcut.map { ProfileHotkey(profileID: profile.id, purpose: .run, shortcut: $0) }].compactMap { $0 }
        }
        for profile in enabledProfiles {
            for action in profile.secondaryActions ?? [] where action.isConfigured {
                if let shortcut = action.hotkey { keys.append(ProfileHotkey(profileID: profile.id, purpose: .secondary, shortcut: shortcut, secondaryActionID: action.id)) }
            }
        }
        if agentCatalogVersion != nil {
            if let shortcut = effectiveCycleShortcuts.previous { keys.append(ProfileHotkey(profileID: AgentCycleShortcuts.identity, purpose: .previous, shortcut: shortcut)) }
            if let shortcut = effectiveCycleShortcuts.next { keys.append(ProfileHotkey(profileID: AgentCycleShortcuts.identity, purpose: .next, shortcut: shortcut)) }
        }
        return keys
    }

    mutating func updateCycleShortcuts(previous: KeyboardShortcut?, next: KeyboardShortcut?) throws {
        var library = self
        library.cycleShortcuts = AgentCycleShortcuts(previous: previous, next: next)
        try library.validate(); self = library
    }

    func cycleTarget(offset: Int) -> ButtonProfile? {
        let enabled = enabledProfiles
        guard !enabled.isEmpty, let index = enabled.firstIndex(where: { $0.id == activeID }) else { return nil }
        let next = ((index + offset) % enabled.count + enabled.count) % enabled.count
        return enabled[next]
    }

    /// Defaults apply only on first migration. Later edits, including unassigned keys, are preserved.
    mutating func assignInitialShortcuts() {
        for index in profiles.indices {
            let key: UInt32
            switch profiles[index].name { case "Codex": key = 18; case "Grok": key = 19; case "Siri": key = 20; default: continue }
            profiles[index].activateShortcut = KeyboardShortcut(keyCode: key, modifiers: 6)
            profiles[index].runShortcut = KeyboardShortcut(keyCode: key, modifiers: 7)
        }
    }

    mutating func updateActiveShortcuts(activate: KeyboardShortcut?, run: KeyboardShortcut?) throws {
        let index = profiles.firstIndex { $0.id == activeID }!
        if profiles[index].builtInSiri == true && (activate != profiles[index].activateShortcut || run != profiles[index].runShortcut) { throw ProfileError.pinnedSiri }
        var next = self
        next.profiles[index].activateShortcut = activate
        next.profiles[index].runShortcut = run
        try next.validate()
        self = next
    }

    static func load(from defaults: UserDefaults = .standard) throws -> Self? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        let library = try JSONDecoder().decode(Self.self, from: data)
        try library.validate()
        return library
    }

    func save(to defaults: UserDefaults = .standard) throws {
        try validate()
        let data = try JSONEncoder().encode(self)
        let legacy = try JSONEncoder().encode(active.settings)
        // Preserve an unreadable previous library before an explicit save.
        if let previous = defaults.data(forKey: Self.defaultsKey),
           (try? Self.load(from: defaults)) == nil {
            defaults.set(previous, forKey: Self.recoveryKey)
        }
        defaults.set(data, forKey: Self.defaultsKey)
        // Keep the old current-settings key compatible with existing installs.
        defaults.set(legacy, forKey: ButtonSettings.defaultsKey)
    }

    mutating func select(_ id: UUID) throws {
        guard profiles.contains(where: { $0.id == id && $0.isEnabled }) else { throw ProfileError.missing }
        activeID = id
    }

    mutating func updateActive(_ settings: ButtonSettings) {
        let index = profiles.firstIndex { $0.id == activeID }!
        var settings = settings
        if profiles[index].builtInSiri == true { settings.action = .openApp; settings.target = Self.siriPath }
        profiles[index].settings = settings
    }

    @discardableResult
    mutating func add(name: String, settings: ButtonSettings) throws -> UUID {
        let name = try checkedName(name)
        var profile = ButtonProfile(name: name, settings: settings)
        profile.automaticActionSelection = active.automaticActionSelection
        profile.additionalButtons = active.additionalButtons
        profile.secondaryActions = active.secondaryActions?.map { var copy = $0; copy.hotkey = nil; return copy }
        profile.additionalButtons = profile.additionalButtons?.map { button in
            var copy = button
            if copy.settings.action == .agentAction, let reference = AgentActionReference(copy.settings.target), reference.profileID == activeID {
                copy.settings.target = AgentActionReference(profileID: profile.id, actionID: reference.actionID).encoded
            }
            return copy
        }
        profiles.append(profile); activeID = profile.id
        if agentCatalogVersion != nil { renumberShortcuts() }
        return profile.id
    }

    mutating func updateButton(_ button: HeadsetButton, in profileID: UUID) throws {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { throw ProfileError.missing }
        guard !button.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, button.name.count <= 60 else { throw ProfileError.invalidName }
        var next = self
        if button.id == "teams" {
            var settings = button.settings
            if next.profiles[index].builtInSiri == true { settings.action = .openApp; settings.target = Self.siriPath }
            next.profiles[index].settings = settings
        } else {
            var buttons = next.profiles[index].additionalButtons ?? []
            buttons.removeAll { $0.id == button.id }
            buttons.append(button)
            next.profiles[index].additionalButtons = buttons
        }
        try next.validate()
        self = next
    }

    mutating func updateSecondaryAction(_ action: AgentSecondaryAction, in profileID: UUID) throws {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { throw ProfileError.missing }
        var next = self
        var actions = next.profiles[index].secondaryActions ?? []
        guard !actions.contains(where: { $0.id != action.id && Self.normalized($0.name) == Self.normalized(action.name) }) else { throw ProfileError.duplicateName }
        if let existing = actions.firstIndex(where: { $0.id == action.id }) { actions[existing] = action } else { actions.append(action) }
        next.profiles[index].secondaryActions = actions
        try next.validate(); self = next
    }
    @discardableResult mutating func installCodexActionPresets(for profileID: UUID) -> Bool {
        guard codexActionPresetsVersion == nil, let index = profiles.firstIndex(where: { $0.id == profileID }) else { return false }
        var actions = profiles[index].secondaryActions ?? []
        for preset in AgentActionPresets.codex {
            let existing = actions.firstIndex { $0.presetID == preset.id || $0.name.lowercased() == preset.name.lowercased() || (preset.id == "voice.start" && $0.name.lowercased() == "voice") }
            var action = existing.map { actions[$0] } ?? AgentSecondaryAction(name: preset.name)
            if existing == nil { action.runAfterHeadset = false }
            action.name = preset.name; action.presetID = preset.id; action.kind = .keyboard
            action.key = KeyboardShortcut(keyCode: preset.key, modifiers: preset.modifiers)
            action.sendGlobally = preset.id == "voice.start"
            if let existing { actions[existing] = action } else { actions.append(action) }
        }
        profiles[index].secondaryActions = actions; codexActionPresetsVersion = 1
        return true
    }

    @discardableResult mutating func migrateAutomaticActions() -> Bool {
        var changed = false
        for index in profiles.indices {
            guard var actions = profiles[index].secondaryActions, actions.contains(where: { $0.runAfterHeadset == nil }) else { continue }
            for actionIndex in actions.indices where actions[actionIndex].runAfterHeadset == nil { actions[actionIndex].runAfterHeadset = true }
            if let voice = actions.firstIndex(where: { $0.name.lowercased() == "voice" }),
               let chat = actions.firstIndex(where: { $0.name.lowercased() == "new chat" }), chat > voice {
                let newChat = actions.remove(at: chat); actions.insert(newChat, at: voice)
            }
            profiles[index].secondaryActions = actions; changed = true
        }
        return changed
    }
    mutating func moveSecondaryAction(_ id: UUID, offset: Int, in profileID: UUID) throws {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == profileID }),
              var actions = profiles[profileIndex].secondaryActions,
              let index = actions.firstIndex(where: { $0.id == id }) else { throw ProfileError.missing }
        let destination = index + offset
        guard actions.indices.contains(destination) else { return }
        let action = actions.remove(at: index); actions.insert(action, at: destination)
        profiles[profileIndex].secondaryActions = actions
    }

    mutating func removeSecondaryAction(_ id: UUID, in profileID: UUID) throws {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { throw ProfileError.missing }
        profiles[index].secondaryActions?.removeAll { $0.id == id }
        if profiles[index].automaticActionSelection == id.uuidString { profiles[index].automaticActionSelection = "none" }
        let removed = AgentActionReference(profileID: profileID, actionID: id).encoded
        for profileIndex in profiles.indices {
            profiles[profileIndex].additionalButtons = profiles[profileIndex].additionalButtons?.map { button in
                var copy = button
                if copy.settings.action == .agentAction && copy.settings.target == removed { copy.settings.action = .none; copy.settings.target = "" }
                return copy
            }
        }
    }

    mutating func removeCustomButton(_ id: String, in profileID: UUID) throws {
        guard id.hasPrefix("custom-"), let index = profiles.firstIndex(where: { $0.id == profileID }) else { throw ProfileError.missing }
        profiles[index].additionalButtons?.removeAll { $0.id == id }
    }

    mutating func renameActive(to name: String) throws {
        guard active.builtInSiri != true else { throw ProfileError.pinnedSiri }
        let name = try checkedName(name, excluding: activeID)
        let index = profiles.firstIndex { $0.id == activeID }!
        profiles[index].name = name
    }

    mutating func deleteActive() throws {
        guard active.builtInSiri != true else { throw ProfileError.pinnedSiri }
        guard profiles.count > 1 else { throw ProfileError.lastProfile }
        let index = profiles.firstIndex { $0.id == activeID }!
        profiles.remove(at: index)
        activeID = profiles[min(index, profiles.count - 1)].id
        if agentCatalogVersion != nil { if !active.isEnabled { activeID = enabledProfiles[0].id }; renumberShortcuts() }
    }

    static let siriPath = "/System/Applications/Siri.app"

    /// One-time migration into the user-managed agent list; never restores agents the user later removes.
    mutating func configureAgentCatalog(_ templates: [(name: String, target: String?)]) throws {
        guard agentCatalogVersion == nil else { return }
        var next = self
        let source = active.settings
        let siriIndex = next.profiles.firstIndex { Self.normalized($0.name) == "siri" }
        var siri = siriIndex.map { next.profiles.remove(at: $0) } ?? ButtonProfile(name: "Siri", settings: source)
        siri.name = "Siri"; siri.builtInSiri = true; siri.enabled = true
        siri.settings.action = .openApp; siri.settings.target = Self.siriPath
        next.profiles.insert(siri, at: 0)
        for template in templates {
            let aliases = template.name == "Grok Bot" ? ["Grok", "Grok Bot"] : [template.name]
            if let index = next.profiles.firstIndex(where: { aliases.map(Self.normalized).contains(Self.normalized($0.name)) }) {
                next.profiles[index].name = template.name
                next.profiles[index].enabled = next.profiles[index].settings.action != .none
            } else {
                var settings = source; settings.action = template.target == nil ? .none : .openApp; settings.target = template.target ?? ""
                var profile = ButtonProfile(name: template.name, settings: settings)
                profile.enabled = template.target != nil
                next.profiles.append(profile)
            }
        }
        for index in next.profiles.indices where next.profiles[index].builtInSiri != true {
            if next.profiles[index].settings.action == .none || next.profiles[index].settings.validationError != nil { next.profiles[index].enabled = false }
        }
        next.agentCatalogVersion = 1
        if !next.active.isEnabled { next.activeID = siri.id }
        next.renumberShortcuts()
        try next.validate(); self = next
    }

    private mutating func renumberShortcuts() {
        let codes: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
        var number = 0
        for index in profiles.indices {
            if profiles[index].isEnabled {
                profiles[index].activateShortcut = number < codes.count ? KeyboardShortcut(keyCode: codes[number], modifiers: 6) : nil
                profiles[index].runShortcut = number < codes.count ? KeyboardShortcut(keyCode: codes[number], modifiers: 7) : nil
                number += 1
            } else { profiles[index].activateShortcut = nil; profiles[index].runShortcut = nil }
        }
    }

    mutating func setAgentEnabled(_ id: UUID, enabled: Bool) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw ProfileError.missing }
        guard profiles[index].builtInSiri != true else { throw ProfileError.pinnedSiri }
        if !enabled && profiles[index].isEnabled && enabledProfiles.count == 1 { throw ProfileError.lastProfile }
        if enabled && (profiles[index].settings.action == .none || profiles[index].settings.validationError != nil) { throw ProfileError.disabledAgent }
        profiles[index].enabled = enabled
        if !enabled && activeID == id { activeID = enabledProfiles[0].id }
        renumberShortcuts()
    }

    mutating func moveAgent(_ id: UUID, offset: Int) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw ProfileError.missing }
        guard profiles[index].builtInSiri != true else { throw ProfileError.pinnedSiri }
        let destination = index + offset
        guard destination >= (agentCatalogVersion == nil ? 0 : 1), destination < profiles.count else { return }
        let profile = profiles.remove(at: index); profiles.insert(profile, at: destination)
        renumberShortcuts()
    }

    mutating func setAutomaticActionSelection(_ selection: String?, for id: UUID) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw ProfileError.missing }
        if let selection, selection != "none" {
            guard profiles[index].secondaryActions?.contains(where: { $0.id.uuidString == selection && $0.isConfigured }) == true else { throw ProfileError.missing }
        }
        profiles[index].automaticActionSelection = selection
    }

    mutating func updateAgent(_ id: UUID, name: String, settings: ButtonSettings) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw ProfileError.missing }
        guard profiles[index].builtInSiri != true else { throw ProfileError.pinnedSiri }
        guard settings.action != .agentAction else { throw ProfileError.recursiveAction }
        let name = try checkedName(name, excluding: id)
        profiles[index].name = name; profiles[index].settings = settings
    }

    @discardableResult mutating func addAgent(name: String) throws -> UUID {
        let name = try checkedName(name)
        var settings = active.settings; settings.action = .none; settings.target = ""
        var profile = ButtonProfile(name: name, settings: settings); profile.enabled = false
        profiles.append(profile)
        return profile.id
    }

    mutating func removeAgent(_ id: UUID) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw ProfileError.missing }
        guard profiles[index].builtInSiri != true else { throw ProfileError.pinnedSiri }
        profiles.remove(at: index)
        if activeID == id { activeID = enabledProfiles[0].id }
        renumberShortcuts()
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private func checkedName(_ value: String, excluding id: UUID? = nil) throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60 else { throw ProfileError.invalidName }
        guard !profiles.contains(where: { $0.id != id && Self.normalized($0.name) == Self.normalized(name) }) else { throw ProfileError.duplicateName }
        return name
    }

    private func validate() throws {
        guard !profiles.isEmpty else { throw ProfileError.empty }
        guard Set(profiles.map(\.id)).count == profiles.count else { throw ProfileError.duplicateID }
        guard profiles.contains(where: { $0.id == activeID }) else { throw ProfileError.missing }
        if agentCatalogVersion != nil {
            guard profiles.first?.builtInSiri == true, profiles.filter({ $0.builtInSiri == true }).count == 1,
                  profiles.first?.name == "Siri", profiles.first?.settings.action == .openApp,
                  profiles.first?.settings.target == Self.siriPath, active.isEnabled else { throw ProfileError.pinnedSiri }
        }
        if agentCatalogVersion != nil && enabledProfiles.contains(where: { $0.settings.action == .none || $0.settings.validationError != nil }) { throw ProfileError.disabledAgent }
        for profile in profiles {
            _ = try checkedName(profile.name, excluding: profile.id)
            guard profile.settings.action != .agentAction else { throw ProfileError.recursiveAction }
            let actions = profile.secondaryActions ?? []
            guard Set(actions.map(\.id)).count == actions.count else { throw ProfileError.duplicateID }
            let extra = profile.additionalButtons ?? []
            guard !extra.contains(where: { $0.id == "teams" }), Set(extra.map(\.id)).count == extra.count else { throw ProfileError.duplicateID }
            let signals = profile.resolvedButtons.flatMap { $0.settings.learnedSignals }.map(\.bindingID)
            guard Set(signals).count == signals.count else { throw ProfileError.buttonConflict }
        }
        guard hotkeys.allSatisfy({ $0.shortcut.isValid }) else { throw ProfileError.invalidShortcut }
        guard Set(hotkeys.map(\.shortcut)).count == hotkeys.count else { throw ProfileError.shortcutConflict }
    }
}
