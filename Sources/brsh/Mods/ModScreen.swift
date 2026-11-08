import SwiftUI
import UniformTypeIdentifiers

struct Mod: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var enabled: Bool
    var fileName: String
    var url: URL { URL.documentsDirectory.appending(path: fileName) }
}

enum ModStore {
    static let file = URL.documentsDirectory.appending(path: "mods.json")

    static func load() -> [Mod] {
        guard let data = try? Data(contentsOf: file),
              let mods = try? JSONDecoder().decode([Mod].self, from: data) else { return [] }
        return mods.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    static func save(_ mods: [Mod]) {
        do {
            try JSONEncoder().encode(mods).write(to: file, options: .atomic)
        } catch {
            log.error("saving mods failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

struct ModScreen: View {
    @State private var isPresented = false
    @State private var selectedFileURL: URL?
    @State private var mods: [Mod] = ModStore.load()
    @State private var patching = false
    @State private var patchedURL: URL?
    @State private var patchStatus: String?
    @State private var downloadProgress: Double?

    var body: some View {
        NavigationStack {
            Form {
                Button("Import mod from zip...") {
                    isPresented = true
                }.fileImporter(
                    isPresented: $isPresented, allowedContentTypes: [.zip],
                    onCompletion: { result in
                        switch result {
                        case .success(let url):
                            guard url.startAccessingSecurityScopedResource() else { return }
                            defer { url.stopAccessingSecurityScopedResource() }

                            do {
                                let dest = URL.documentsDirectory.appending(
                                    path: url.lastPathComponent)
                                try? FileManager.default.removeItem(at: dest)  // overwrite if it exists
                                try FileManager.default.copyItem(at: url, to: dest)

                                let name = url.deletingPathExtension().lastPathComponent
                                mods.removeAll { $0.fileName == dest.lastPathComponent }  // re-import replaces
                                mods.append(Mod(name: name, enabled: true, fileName: dest.lastPathComponent))
                            } catch {
                                print("Import failed: \(error)")
                            }

                        case .failure(let error):
                            print("Failed: \(error.localizedDescription)")
                        }
                    })

                Section("Manage Mods") {
                    ForEach(mods) { mod in
                        Toggle(mod.name, isOn: enabledBinding(for: mod.id))
                    }
                    .onMove { from, to in
                        mods.move(fromOffsets: from, toOffset: to)
                    }
                    .onDelete { offsets in
                        for i in offsets {
                            try? FileManager.default.removeItem(at: mods[i].url)
                        }
                        mods.remove(atOffsets: offsets)
                    }

                    if mods.isEmpty {
                        Text("No mods yet")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Roblox") {
                    Button {
                        patching = true
                        patchStatus = nil
                        let enabled = mods.filter(\.enabled).map(\.url)
                        Task {
                            patchedURL = await patchRoblox(
                                modZips: enabled,
                                status: { line in Task { @MainActor in patchStatus = line } },
                                downloadProgress: { value in Task { @MainActor in downloadProgress = value } }
                            )
                            patching = false
                            downloadProgress = nil  // a late poll update can't leave the bar up
                        }
                    } label: {
                        HStack {
                            Text(patching ? "Patching… (please!!! keep brsh open!!!)" : "Patch roblox with enabled mods")
                            if patching { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(patching)

                    if let downloadProgress {
                        ProgressView(value: downloadProgress) {
                            Text("\(Int(downloadProgress * 100))%").font(.footnote)
                        }
                    }

                    if let patchStatus {
                        Text(patchStatus)
                            .font(.footnote)
                            .foregroundStyle(patchStatus.hasPrefix("Failed") ? .red : .secondary)
                    }

                    if let patchedURL {
                        ShareLink("Open patched IPA (LiveContainer)", item: patchedURL)
                    }
                }
            }
            .navigationTitle("Mods")
            .toolbar { EditButton() }
            .onChange(of: mods) { _, newMods in ModStore.save(newMods) }  // add/delete/toggle/reorder
        }
    }

    private func enabledBinding(for id: Mod.ID) -> Binding<Bool> {
        Binding(
            get: { mods.first { $0.id == id }?.enabled ?? false },
            set: { newValue in
                if let i = mods.firstIndex(where: { $0.id == id }) { mods[i].enabled = newValue }
            }
        )
    }
}
