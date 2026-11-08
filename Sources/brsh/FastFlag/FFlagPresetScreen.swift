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
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fuck Telementry").font(.headline)
                        Text("Disable all telementry & Data collecting").font(.subheadline)
                            .foregroundStyle(
                                .secondary)
                    }
                }

                Toggle(isOn: $lighting) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Complete Post-Processing & Shadow Stripping").font(.headline)
                        Text(
                            "Disables depth of field, bloom, sun rays, global shadows, and blur shaders"
                        ).font(.subheadline)
                            .foregroundStyle(
                                .secondary)
                    }
                }

                Toggle(isOn: $skyGray) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Make the sky gray").font(.headline)
                        Text(
                            "description"
                        ).font(.subheadline)
                            .foregroundStyle(
                                .secondary)
                    }
                }

                Toggle(isOn: $pauseVoxelizer) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pause voxelizer").font(.headline)
                        Text("Pauses the dynamic voxel lighting updates").font(.subheadline)
                            .foregroundStyle(
                                .secondary)
                    }
                }

                Stepper(value: $parallelWorkers, in: 1...25) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Parallel Lua Worker Thread Allocation").font(.headline)
                            Text(
                                "Forces the engine to utilize a specific number of background worker threads for parallel script execution and internal state management"
                            ).font(.subheadline)
                                .foregroundStyle(
                                    .secondary)
                        }
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
                        pauseVoxelizer: pauseVoxelizer, msaa: msaa, skyGray: skyGray, pararellWorkers: parallelWorkers)
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
