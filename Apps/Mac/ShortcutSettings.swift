import AppKit
import SwiftUI

/// Settings › Shortcuts: every menu command, by menu, with its shortcut, to change. Click a
/// shortcut and press the new keys; Escape leaves it as it was, Delete removes it.
struct ShortcutSettings: View {
    @ObservedObject private var shortcuts = ShortcutStore.shared
    /// The command whose shortcut is being recorded.
    @State private var recording: ShortcutAction?
    /// What the last change did besides (a shortcut moved from another command).
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text("Click a shortcut and press the keys for it. Escape leaves it as it was; Delete removes it.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Restore Defaults") {
                    shortcuts.resetAll()
                    notice = nil
                }
                .disabled(shortcuts.changes.isEmpty)
            }
            if let notice {
                Label(notice, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
            ForEach(ShortcutAction.menus, id: \.self) { menu in
                VStack(alignment: .leading, spacing: 6) {
                    Text(menu == "Highlight List Item" ? "Format › Highlight List Item" : menu)
                        .font(.body.weight(.bold))
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        ForEach(ShortcutAction.allCases.filter { $0.menu == menu }) { action in
                            GridRow {
                                Text(action.title)
                                    .frame(minWidth: 220, alignment: .leading)
                                ShortcutRecorder(action: action, recording: $recording, notice: $notice)
                                Button {
                                    shortcuts.reset(action)
                                    notice = nil
                                } label: {
                                    Image(systemName: "arrow.uturn.backward")
                                }
                                .buttonStyle(.borderless)
                                .help("Back to \(action.defaultShortcut?.label ?? "none")")
                                .opacity(shortcuts.isChanged(action) ? 1 : 0)
                                .disabled(!shortcuts.isChanged(action))
                            }
                        }
                    }
                }
            }
        }
        .onDisappear { recording = nil }
    }
}

/// A command's shortcut, as a button; clicked, it records the next keys pressed.
private struct ShortcutRecorder: View {
    let action: ShortcutAction
    @Binding var recording: ShortcutAction?
    @Binding var notice: String?
    @ObservedObject private var shortcuts = ShortcutStore.shared
    @State private var monitor: Any?

    private var isRecording: Bool { recording == action }

    var body: some View {
        Button {
            recording = isRecording ? nil : action
        } label: {
            Text(isRecording ? "Type a shortcut…" : shortcuts.label(for: action) ?? "None")
                .monospacedDigit()
                .foregroundStyle(isRecording ? Color.accentColor : shortcuts.label(for: action) == nil ? .secondary : .primary)
                .frame(minWidth: 120)
        }
        .onChange(of: isRecording) { recording in
            if recording { startRecording() } else { stopRecording() }
        }
        .onDisappear { stopRecording() }
    }

    /// Takes the next key pressed, before the menus (or anything else) can.
    private func startRecording() {
        stopRecording()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let plain = event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
            if event.keyCode == 53 { // Escape
                recording = nil
            } else if plain, event.keyCode == 51 || event.keyCode == 117 { // Delete, Forward Delete
                shortcuts.set(nil, for: action)
                notice = nil
                recording = nil
            } else if let shortcut = Shortcut(event: event) {
                if let displaced = shortcuts.set(shortcut, for: action) {
                    notice = "\(shortcut.label) was used by \(displaced.title), which now has none."
                } else {
                    notice = nil
                }
                recording = nil
            } else {
                NSSound.beep() // A shortcut needs ⌘ or ⌃.
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
