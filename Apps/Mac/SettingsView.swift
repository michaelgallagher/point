import SwiftUI
import VaultKit

/// Imprint's Settings window (⌘,): grouped settings, each with its label above its options.
struct SettingsView: View {
    @EnvironmentObject private var store: VaultStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection("Sidebar") {
                Setting("Layout") {
                    Picker("Layout", selection: $store.browsingStyle) {
                        Text("One column: folders, tags and notes in one list").tag(VaultModel.BrowsingStyle.singleColumn)
                        Text("Two columns: folders and tags beside the notes").tag(VaultModel.BrowsingStyle.twoColumns)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
                Setting("Density") {
                    Picker("Density", selection: $store.sidebarDensity) {
                        Text("Comfortable").tag(VaultModel.SidebarDensity.comfortable)
                        Text("Compact").tag(VaultModel.SidebarDensity.compact)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
                Setting("Folders and tags, in two columns") {
                    Picker("Folders and tags, in two columns", selection: $store.treeLayout) {
                        Text("Together, folders above tags").tag(VaultModel.TreeLayout.stacked)
                        Text("One at a time, with a switch").tag(VaultModel.TreeLayout.toggle)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
                .disabled(store.browsingStyle != .twoColumns)
                Toggle("Swipe sideways with two fingers to show and hide it", isOn: $store.swipesSidebar)
            }

            Divider()

            SettingsSection("Sorting") {
                HStack(alignment: .top, spacing: 32) {
                    Setting("Folders and tags") {
                        Picker("Folders and tags", selection: $store.tagOrder) {
                            Text("Name").tag(VaultModel.TagOrder.name)
                            Text("Date Modified").tag(VaultModel.TagOrder.modified)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Setting("Notes") {
                        Picker("Notes", selection: $store.sort) {
                            Text("Date Edited").tag(NoteSort.modified)
                            Text("Date Created").tag(NoteSort.created)
                            Text("Title").tag(NoteSort.title)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }

            Divider()

            SettingsSection("Note list") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Show dates", isOn: $store.showsDateInList)
                    Picker("Date shown", selection: $store.listDate) {
                        Text("Date edited").tag(VaultModel.ListDate.edited)
                        Text("Date created").tag(VaultModel.ListDate.created)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    .padding(.leading, 20)
                    .disabled(!store.showsDateInList)
                    Toggle("Show tags", isOn: $store.showsTagsInList)
                }
            }

            Divider()

            SettingsSection("Text") {
                Toggle("Show each note's folders above its title", isOn: $store.showsNotePath)
                Setting("Size") {
                    HStack {
                        Text("\(Int((store.textScale * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .leading)
                        Stepper("Text size", onIncrement: store.makeTextBigger, onDecrement: store.makeTextSmaller)
                            .labelsHidden()
                        Button("Reset") { store.textScale = 1 }
                            .disabled(store.textScale == 1)
                    }
                }
            }
        }
        .padding(28)
        .frame(width: 560, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A titled group of settings.
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
    }
}

/// One setting: its label, with its options below.
private struct Setting<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .foregroundStyle(.secondary)
            content
        }
    }
}
