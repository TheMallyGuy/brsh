import SwiftUI

struct Config: Codable {
    var githubToken: String  // store as plain text :skull:
}

enum SettingsStore {
    static let file = URL.documentsDirectory.appending(path: "cfgs.json")

    static func load() -> Config {
        guard let data = try? Data(contentsOf: file),
            let cfg = try? JSONDecoder().decode(Config.self, from: data)
        else {
            return Config(githubToken: "")
        }
        return cfg
    }

    static func save(_ cfg: Config) {
        do {
            try JSONEncoder().encode(cfg).write(to: file, options: .atomic)
        } catch {
            log.error("saving cfg failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

struct SettingsScreen: View {
    @State private var githubToken: String = SettingsStore.load().githubToken

    @State private var showResetAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Github token") {
                    SecureField("Github Token", text: $githubToken)
                }

                Section("About") {
                    LabeledContent(
                        "Version",
                        value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
                    Link("Github", destination: URL(string: "https://github.com/TheMallyGuy/living-in-the-bushes")!)
                }

                Section {
                    Button("Reset All Settings", role: .destructive) {
                        showResetAlert = true
                    }
                }
            }.onChange(of: githubToken) { oldValue, newValue in
                SettingsStore.save(Config(githubToken: newValue))
            }
            .navigationTitle("Settings")
            .alert("Reset settings?", isPresented: $showResetAlert) {
                Button("Reset", role: .destructive) { resetAll() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    func resetAll() {
        githubToken = ""
    }
}
