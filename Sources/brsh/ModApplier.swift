import Foundation
import os

let log = Logger(subsystem: "com.la66483g8a.brsh", category: "app")

struct AssetsResponse: Codable {
    let assets: [Asset]
}

struct Asset: Codable {
    let name: String
    let url: String
    let browser_download_url: String
    let size: Int
}

private let ipaPrefix = "com.roblox.robloxmobile-"

private func cachedIpas() -> [URL] {
    let files = (try? FileManager.default.contentsOfDirectory(
        at: URL.documentsDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    return files
        .filter { $0.lastPathComponent.hasPrefix(ipaPrefix) && $0.pathExtension == "ipa" }
        .sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
}

private func fileSize(_ url: URL) -> Int {
    (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
}

/// Returns the latest Roblox IPA, downloading only if that version isn't cached.
/// Offline or API error: falls back to the newest cached IPA.
@discardableResult
func downloadRobloxIpa() async -> URL? {
    log.notice("checking latest roblox")
    guard
        let asset_rel = URL(
            string:
                "https://api.github.com/repos/Roblox-DeployHistory-Updates/ios-runner/releases/latest"
        )
    else { return nil }

    do {
        let (data, _) = try await URLSession.shared.data(from: asset_rel)
        let assets = try JSONDecoder().decode(AssetsResponse.self, from: data)

        for asset in assets.assets {
            log.notice("asset name: \(asset.name, privacy: .public)")
            guard asset.name.hasSuffix(".ipa"), let downloadURL = URL(string: asset.browser_download_url) else { continue }

            let ipaFileURL = URL.documentsDirectory.appending(path: asset.name)

            if fileSize(ipaFileURL) == asset.size {
                log.notice("using cached IPA: \(asset.name, privacy: .public)")
                return ipaFileURL
            }

            log.notice("downloading \(asset.name, privacy: .public)")
            // download(from:) streams to a temp file instead of holding ~100 MB in memory
            let (tempFile, _) = try await URLSession.shared.download(from: downloadURL)

            // move out of tmp (iOS deletes it) into Documents
            try? FileManager.default.removeItem(at: ipaFileURL)
            try FileManager.default.moveItem(at: tempFile, to: ipaFileURL)
            log.notice("Downloaded Roblox IPA to: \(ipaFileURL.path, privacy: .public)")

            for old in cachedIpas() where old != ipaFileURL {
                try? FileManager.default.removeItem(at: old)
                log.notice("removed old IPA: \(old.lastPathComponent, privacy: .public)")
            }
            return ipaFileURL
        }
        log.error("no .ipa asset in latest release")
    } catch {
        log.error("Failed: \(error.localizedDescription, privacy: .public)")
    }

    if let cached = cachedIpas().first {
        log.notice("falling back to cached IPA: \(cached.lastPathComponent, privacy: .public)")
        return cached
    }
    return nil
}

func patchRoblox(modZips: [URL]) async -> URL? {
    guard let ipaURL = await downloadRobloxIpa() else { return nil }

    return await Task.detached(priority: .userInitiated) { () -> URL? in
        do {
            log.notice("patching with \(modZips.count) mod(s)")
            let out = URL.documentsDirectory.appending(path: "Roblox-patched.ipa")
            let start = Date()
            let files = try IpaPatcher.patch(ipa: ipaURL, mods: modZips, output: out)
            log.notice("patched \(files) file(s) in \(Date().timeIntervalSince(start), format: .fixed(precision: 2))s")
            log.notice("patched IPA: \(out.path, privacy: .public)")
            return out
        } catch {
            log.error("patch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }.value
}
