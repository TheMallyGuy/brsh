import SwiftUI

struct FFlagScreen: View {
    @State private var text = FFlagStore.load()
    @State private var message: String?
    @State private var fflagRemote: String = ""
    @State private var errorMessageURL: String?

    var body: some View {
        Form {
            Text(
                "FFlags require an custom tweak. You can view the guide on the readme to install the tweak."
            )
            Text("The allowlist doesnt apply for ios due to how the tweak edit fflags")

            NavigationLink("Fastflags Presets") { FFlagPresetScreen() }

            Section {
                TextField("https://raw.githubusercontent.com/The.....", text: $fflagRemote)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Load") {
                    Task {
                        await loadRemote()
                    }
                }
                if let errorMessageURL { Text(errorMessageURL).foregroundStyle(.red) }
            } header: {
                Text("Import remote Flags")
            } footer: {
                Text("Overwrite the current flags with the remote flag url provided")
            }

            Section {
                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(maxHeight: 300)
            } header: {
                Text("fflags.json")
            } footer: {
                Text(
                    "Served at http://127.0.0.1:8777/fflags.json, you may open Roblox with the tweak now"
                )
            }

            Section {
                Button("Save") {
                    message = FFlagStore.save(text) ?? "Saved"
                }
                Button("Reset to defaults", role: .destructive) {
                    text = FFlagStore.defaultJSON
                    message = FFlagStore.save(text) ?? "Reset"
                }
                if let message {
                    Text(message).foregroundStyle(
                        message == "Saved" || message == "Reset" ? .green : .red)
                }
            }
        }
        .navigationTitle("FastFlags")
        .onAppear { refreshFflags() }
    }

    func refreshFflags() {
        text = FFlagStore.load()
    }

    func loadRemote() async {
        errorMessageURL = nil
        guard let url = URL(string: fflagRemote.trimmingCharacters(in: .whitespacesAndNewlines)),
            url.scheme == "https" || url.scheme == "http", url.host != nil
        else {
            errorMessageURL = "Invalid URL"
            return
        }

        do {
            let flags = try await fetchFlags(url: url)
            message = FFlagStore.save(flags) ?? "Saved"
            refreshFflags()
        } catch {
            errorMessageURL = error.localizedDescription
        }
    }
}
