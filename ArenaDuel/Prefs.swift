//
//  Prefs.swift
//  ArenaDuel
//
//  Created by Ethan Leung on 23/11/2026.
//

import SwiftUI
import AppKit

/// Saved settings, readable from anywhere (the game reads them live).
enum Prefs {
    static var sensitivity: Double { UserDefaults.standard.object(forKey: "sensitivity") as? Double ?? 1.0 }
    static var volume: Double { UserDefaults.standard.object(forKey: "volume") as? Double ?? 0.8 }
    static var fov: Double { UserDefaults.standard.object(forKey: "fov") as? Double ?? 75 }
    static var adsToggle: Bool { UserDefaults.standard.bool(forKey: "adsToggle") }
    static var showStats: Bool { UserDefaults.standard.object(forKey: "showStats") as? Bool ?? true }
    static var shadows: Bool { UserDefaults.standard.object(forKey: "shadows") as? Bool ?? true }
}

// MARK: - Loadout

/// The three equipped weapons: [primary, secondary, melee], as indices into `Weapon.all`.
enum Loadout {
    static func options(for slot: Int) -> [Int] {
        Weapon.all.indices.filter { Weapon.all[$0].slot == slot }
    }

    static func load() -> [Int] {
        (0..<3).map { slot in
            let choices = options(for: slot)
            if let saved = UserDefaults.standard.object(forKey: "loadout_\(slot)") as? Int, choices.contains(saved) {
                return saved
            }
            return choices[0]
        }
    }

    static func set(slot: Int, weapon: Int) {
        UserDefaults.standard.set(weapon, forKey: "loadout_\(slot)")
    }
}

struct StatBar: View {
    let label: String
    let value: Double
    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .frame(width: 40, alignment: .leading)
                .opacity(0.6)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12)).frame(width: 70, height: 5)
                Capsule().fill(Color.accentColor)
                    .frame(width: 70 * CGFloat(max(0.04, min(1, value))), height: 5)
            }
        }
    }
}

struct WeaponCard: View {
    let weapon: Weapon
    let selected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(weapon.name.uppercased())
                .font(.system(size: 13, weight: .heavy, design: .rounded))
            StatBar(label: "POWER", value: weapon.power)
            StatBar(label: "SPEED", value: weapon.rate)
            StatBar(label: "RANGE", value: weapon.reach)
            StatBar(label: "ACCURACY", value: weapon.accuracy)
        }
        .padding(10)
        .frame(width: 150, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2))
    }
}

/// Pick one primary, one secondary and one melee weapon.
struct LoadoutPicker: View {
    @State private var chosen = Loadout.load()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(0..<3, id: \.self) { slot in
                VStack(alignment: .leading, spacing: 6) {
                    Text(Weapon.slotNames[slot].uppercased())
                        .font(.caption.bold())
                        .opacity(0.6)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10, alignment: .leading)], alignment: .leading, spacing: 10) {
                        ForEach(Loadout.options(for: slot), id: \.self) { i in
                            Button {
                                Loadout.set(slot: slot, weapon: i)
                                chosen = Loadout.load()
                            } label: {
                                WeaponCard(weapon: Weapon.all[i], selected: chosen[slot] == i)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Key bindings

enum KeyAction: String, CaseIterable, Identifiable {
    case forward, back, left, right, jump, sprint, slide, aim, fire, reload, scoreboard
    case weapon1, weapon2, weapon3

    var id: String { rawValue }

    var weaponSlot: Int? {
        switch self {
        case .weapon1: return 0
        case .weapon2: return 1
        case .weapon3: return 2
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .forward: return "Move forward"
        case .back:    return "Move back"
        case .left:    return "Move left"
        case .right:   return "Move right"
        case .jump:    return "Jump"
        case .sprint:  return "Sprint"
        case .slide:   return "Slide / crouch"
        case .aim:     return "Aim down sights"
        case .fire:    return "Fire"
        case .reload:  return "Reload"
        case .scoreboard: return "Scoreboard (hold)"
        case .weapon1: return "Primary weapon"
        case .weapon2: return "Secondary weapon"
        case .weapon3: return "Melee weapon"
        }
    }

    var defaultCode: UInt16 {
        switch self {
        case .forward: return 13   // W
        case .back:    return 1    // S
        case .left:    return 0    // A
        case .right:   return 2    // D
        case .jump:    return 49   // Space
        case .sprint:  return 56   // Left Shift
        case .slide:   return 8    // C
        case .aim:     return 12   // Q
        case .fire:    return 3    // F
        case .reload:  return 15   // R
        case .scoreboard: return 48   // Tab
        case .weapon1: return 18   // 1
        case .weapon2: return 19   // 2
        case .weapon3: return 20   // 3
        }
    }
}

enum Keybinds {
    /// True while the settings screen is waiting for a key press, so the game ignores keys.
    static var listening = false

    static func load() -> [KeyAction: UInt16] {
        var out: [KeyAction: UInt16] = [:]
        for a in KeyAction.allCases {
            if let v = UserDefaults.standard.object(forKey: "key_\(a.rawValue)") as? Int {
                out[a] = UInt16(v)
            } else {
                out[a] = a.defaultCode
            }
        }
        return out
    }

    /// Binds a key. If another action already used it, the two swap keys.
    static func set(_ action: KeyAction, _ code: UInt16) {
        let current = load()
        let old = current[action] ?? action.defaultCode
        for (other, c) in current where other != action && c == code {
            UserDefaults.standard.set(Int(old), forKey: "key_\(other.rawValue)")
        }
        UserDefaults.standard.set(Int(code), forKey: "key_\(action.rawValue)")
    }

    static func reset() {
        for a in KeyAction.allCases { UserDefaults.standard.removeObject(forKey: "key_\(a.rawValue)") }
    }

    /// Modifier keys (Shift, Control...) arrive as flag changes instead of key presses.
    static func modifierFlag(for code: UInt16) -> NSEvent.ModifierFlags? {
        switch code {
        case 56, 60: return .shift
        case 59, 62: return .control
        case 58, 61: return .option
        case 55, 54: return .command
        default:     return nil
        }
    }

    static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete",
        53: "Esc", 54: "R-Cmd", 55: "Cmd", 56: "Shift", 57: "Caps", 58: "Option",
        59: "Control", 60: "R-Shift", 61: "R-Option", 62: "R-Control",
        123: "Left", 124: "Right", 125: "Down", 126: "Up",
    ]

    static func label(_ code: UInt16) -> String { names[code] ?? "Key \(code)" }
}

// MARK: - Settings UI

struct KeybindsForm: View {
    @State private var codes = Keybinds.load()
    @State private var listening: KeyAction?
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Controls").font(.headline)
                Spacer()
                Button("Reset keys") {
                    stopListening()
                    Keybinds.reset()
                    codes = Keybinds.load()
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 8) {
                ForEach(KeyAction.allCases) { a in
                    HStack {
                        Text(a.title).font(.callout).lineLimit(1)
                        Spacer()
                        Button(listening == a ? "Press a key..." : Keybinds.label(codes[a] ?? a.defaultCode)) {
                            startListening(a)
                        }
                        .frame(minWidth: 96)
                    }
                }
            }
            Text("Left click also fires and right click also aims. The mouse wheel switches weapon.")
                .font(.caption)
                .opacity(0.65)
        }
        .onDisappear { stopListening() }
    }

    private func startListening(_ action: KeyAction) {
        stopListening()
        listening = action
        Keybinds.listening = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { e in
            if e.type == .keyDown {
                if e.keyCode == 53 { stopListening(); return nil }       // Esc cancels
                assign(action, e.keyCode)
            } else if let flag = Keybinds.modifierFlag(for: e.keyCode), e.modifierFlags.contains(flag) {
                assign(action, e.keyCode)
            }
            return nil
        }
    }

    private func assign(_ action: KeyAction, _ code: UInt16) {
        Keybinds.set(action, code)
        codes = Keybinds.load()
        stopListening()
    }

    private func stopListening() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        listening = nil
        Keybinds.listening = false
    }
}

/// Sliders, toggles and key bindings, shared by the lobby settings sheet and the pause menu.
struct SettingsForm: View {
    @AppStorage("sensitivity") private var sensitivity = 1.0
    @AppStorage("volume") private var volume = 0.8
    @AppStorage("fov") private var fov = 75.0
    @AppStorage("adsToggle") private var adsToggle = false
    @AppStorage("showStats") private var showStats = true
    @AppStorage("shadows") private var shadows = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mouse sensitivity: \(sensitivity, specifier: "%.1f")x")
                Slider(value: $sensitivity, in: 0.3...3)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Volume: \(Int(volume * 100))%")
                Slider(value: $volume, in: 0...1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Field of view: \(Int(fov))°")
                Slider(value: $fov, in: 60...100)
            }
            Toggle("Toggle aim (instead of holding the aim button)", isOn: $adsToggle)
            Toggle("Shadows (turn off if the game stutters)", isOn: $shadows)
            Toggle("Show FPS and network stats", isOn: $showStats)
            Divider()
            KeybindsForm()
        }
    }
}
