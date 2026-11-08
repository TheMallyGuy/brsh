import SwiftUI

struct MsaaOption: Identifiable, Hashable {
    let id: Int
    let title: String
}

struct FFlagPresetScreen: View {
    @State private var text = FFlagStore.load()
    @State private var message: String?
    @State private var noTelemetry = FFlagPreset.noTelemetry()
    @State private var skyGray = Bool(FFlagPreset.skyGray() ?? false)
    @State private var pauseVoxelizer = Bool(FFlagPreset.pauseVoxelizer() ?? false)
    @State private var msaa: Int = Int(FFlagPreset.msaa() ?? 0)
    @State private var lighting: Bool = FFlagPreset.lighting()
    @State private var parallelWorkers: Int = Int(FFlagPreset.parallelWorkers() ?? 8)

    let options = [
        MsaaOption(id: 0, title: "Auto (or disabled)"),
        MsaaOption(id: 1, title: "x1"),
        MsaaOption(id: 2, title: "x2"),
        MsaaOption(id: 4, title: "x4"),
        MsaaOption(id: 8, title: "x8"),
    ]

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $noTelemetry) {
                    SettingLabel(
                        title: "Fuck Telementry",
                        subtitle: "Disable all telementry & Data collecting"
                    )
                }

                Toggle(isOn: $lighting) {
                    SettingLabel(
                        title: "Complete Post-Processing & Shadow Stripping",
                        subtitle:
                            "Disables depth of field, bloom, sun rays, global shadows, and blur shaders"
                    )
                }

                Toggle(isOn: $skyGray) {
                    SettingLabel(
                        title: "Make the sky gray",
                        subtitle:
                            "description"
                    )
                }

                Toggle(isOn: $pauseVoxelizer) {
                    SettingLabel(
                        title: "Pause voxelizer",
                        subtitle:
                            "Pauses the dynamic voxel lighting updates"
                    )
                }

                Stepper(value: $parallelWorkers, in: 1...25) {
                    HStack {
                        SettingLabel(
                            title: "Parallel Lua Worker Thread Allocation",
                            subtitle:
                                "Forces the engine to utilize a specific number of background worker threads for parallel script execution and internal state management"
                        )
                        Spacer()
                        Text("\(parallelWorkers) workers")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Picker("Anti-Aliasing", selection: $msaa) {
                        ForEach(options) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                } footer: {
                    Text(
                        "Applies MSAA beyond the standard pipeline limits. Higher values look smoother but may reduce performance"
                    )
                }

            } header: {
                Text("Presets")
            }

            Section {
                Button("Save") {
                    if let err = FFlagPreset.apply(
                        noTelemetry: noTelemetry, lighting: lighting,
                        pauseVoxelizer: pauseVoxelizer, msaa: msaa, skyGray: skyGray,
                        pararellWorkers: parallelWorkers)
                    {
                        message = err
                    } else {
                        text = FFlagStore.load()
                        message = "Saved"
                    }
                }
                Button("Reset to defaults", role: .destructive) {
                    text = FFlagStore.defaultJSON
                    message = FFlagStore.save(text) ?? "Reset"
                    refreshToggles()
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

    private func refreshToggles() {
        noTelemetry = FFlagPreset.noTelemetry()
        lighting = FFlagPreset.lighting()
        pauseVoxelizer = FFlagPreset.pauseVoxelizer() ?? false
        msaa = FFlagPreset.msaa() ?? 0
    }
}
