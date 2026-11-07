import SwiftUI

struct FFlagScreen: View {
    @State private var text = FFlagStore.load()
    @State private var message: String?

    var body: some View {
        Form {
            Text("FFlags require an custom tweak. You can view the guide on the readme to install the tweak.")
            Section {
                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(maxHeight: 300)
            } header: {
                Text("fflags.json")
            } footer: {
                Text("Served at http://127.0.0.1:8777/fflags.json, you may open Roblox with the tweak now")
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
                    Text(message).foregroundStyle(message == "Saved" || message == "Reset" ? .green : .red)
                }
            }
        }
        .navigationTitle("FastFlags")
    }
}
