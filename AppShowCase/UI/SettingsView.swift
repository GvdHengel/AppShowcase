import SwiftUI

/// Instellingenvenster (⌘,).
struct SettingsView: View {
    @Environment(AndroidDiscovery.self) private var androidDiscovery

    @AppStorage(AppSettingsKey.autoOpenWindows) private var autoOpenWindows = true
    @AppStorage(AppSettingsKey.copyScreenshotToClipboard) private var copyScreenshotToClipboard = true
    @AppStorage(AppSettingsKey.androidQuality) private var androidQuality = AndroidQuality.normal.rawValue

    var body: some View {
        Form {
            Section("Algemeen") {
                Toggle("Venster openen bij aansluiten van een toestel", isOn: $autoOpenWindows)
                Toggle("Schermafbeelding ook op het klembord zetten", isOn: $copyScreenshotToClipboard)
            }

            Section {
                Picker("Beeldkwaliteit", selection: $androidQuality) {
                    ForEach(AndroidQuality.allCases) { quality in
                        Text(quality.name).tag(quality.rawValue)
                    }
                }
                LabeledContent("adb") {
                    Text(androidDiscovery.adbPath ?? "niet gevonden")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                LabeledContent("scrcpy-server", value: AndroidDiscovery.scrcpyVersion)
            } header: {
                Text("Android")
            } footer: {
                Text("Een andere beeldkwaliteit geldt vanaf de volgende verbinding (Opnieuw proberen of opnieuw aansluiten).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Bestanden") {
                LabeledContent("Schermafbeeldingen") {
                    Button("Toon in Finder") { OutputFolders.reveal(.picturesDirectory) }
                }
                LabeledContent("Opnames") {
                    Button("Toon in Finder") { OutputFolders.reveal(.moviesDirectory) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}
