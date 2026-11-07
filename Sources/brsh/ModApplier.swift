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
}

@discardableResult
func downloadRobloxIpa() async -> URL? {
    log.notice("downloading roblox")
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

            // download(from:) streams to a temp file instead of holding ~200 MB in memory
            let (tempFile, _) = try await URLSession.shared.download(from: downloadURL)

            // move out of tmp (iOS deletes it) into Documents
            let docs = URL.documentsDirectory
            let ipaFileURL = docs.appending(path: asset.name)
            try? FileManager.default.removeItem(at: ipaFileURL)
            try FileManager.default.moveItem(at: tempFile, to: ipaFileURL)

            log.notice("Downloaded Roblox IPA to: \(ipaFileURL.path, privacy: .public)")
            return ipaFileURL
        }
        log.error("no .ipa asset in latest release")
    } catch {
        log.error("Failed: \(error.localizedDescription, privacy: .public)")
    }
    return nil
}
