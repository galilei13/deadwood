import AppKit
import SwiftUI

@main
struct DeadwoodApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .defaultSize(width: 1200, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Folder…") {
                    model.isFolderPickerPresented = true
                }
                .keyboardShortcut("o")
            }

            CommandMenu("Scan") {
                Button("Rescan") {
                    model.rescan()
                }
                .keyboardShortcut("r")
                .disabled(model.scannedRoot == nil || model.isScanning)

                Button("Stop Scan") {
                    model.cancelScan()
                }
                .keyboardShortcut(".")
                .disabled(!model.isScanning)

                Divider()

                Button("Quick Look") {
                    model.quickLookSelection()
                }
                .keyboardShortcut("y")
                .disabled(model.selectedNodes.isEmpty)

                Button("Reveal in Finder") {
                    model.revealSelectionInFinder()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.selectedNodes.isEmpty)

                Button("Copy Path") {
                    model.copySelectionPaths()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model.selectedNodes.isEmpty)

                Button("Move to Trash") {
                    model.trashSelection()
                }
                .keyboardShortcut(.delete)
                .disabled(model.selectedNodes.isEmpty || model.isDeleting)
            }

            CommandGroup(after: .toolbar) {
                ForEach(Array(ViewMode.allCases.enumerated()), id: \.element) { index, mode in
                    Button(mode.title) {
                        model.viewMode = mode
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                    .disabled(model.scannedRoot == nil)
                }
                Divider()
            }
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed so `swift run` (no bundle) still shows a real foreground app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct SettingsView: View {
    @AppStorage(ScanOptions.defaultsIncludeHiddenKey) private var includeHiddenFiles = true
    @AppStorage(ScanOptions.defaultsShowPackagesKey) private var showPackageContents = false

    var body: some View {
        Form {
            Section {
                Toggle("Include hidden files", isOn: $includeHiddenFiles)
                Text("Counts invisible files and folders (like caches and .git folders) so sizes match real disk usage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Show package contents", isOn: $showPackageContents)
                Text("Expands apps and other bundles into their inner files. Their total size is always counted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Changes apply to the next scan.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section {
                Button("Open Full Disk Access Settings…") {
                    FileActions.openFullDiskAccessSettings()
                }
                Text("Grant Deadwood Full Disk Access to scan protected folders like Mail, Messages and Time Machine backups.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
    }
}
