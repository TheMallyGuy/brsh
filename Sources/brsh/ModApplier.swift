import Foundation
import Synchronization
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
    let files =
        (try? FileManager.default.contentsOfDirectory(
            at: URL.documentsDirectory, includingPropertiesForKeys: [.contentModificationDateKey]))
        ?? []
    return
        files
        .filter { $0.lastPathComponent.hasPrefix(ipaPrefix) && $0.pathExtension == "ipa" }
        .sorted {
            let a =
                (try? $0.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
            let b =
                (try? $1.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
            return a > b
        }
}

private func fileSize(_ url: URL) -> Int {
    (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
}


@discardableResult
func downloadRobloxIpa(
    status: @escaping PatchStatus = { _ in },
    progress: @escaping @Sendable (Double?) -> Void = { _ in }  // 0...1 while downloading, nil after
) async -> URL? {
    log.notice("checking latest roblox")
    status("Checking latest Roblox")
    guard
        let asset_rel = URL(
            string:
                "https://api.github.com/repos/Roblox-DeployHistory-Updates/ios-runner/releases/latest"
        )
    else { return nil }

    do {
        let token = SettingsStore.load().githubToken

        var request = URLRequest(url: asset_rel)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)

        let assets = try JSONDecoder().decode(AssetsResponse.self, from: data)

        for asset in assets.assets {
            log.notice("asset name: \(asset.name, privacy: .public)")
            guard asset.name.hasSuffix(".ipa"),
                let downloadURL = URL(string: asset.browser_download_url)
            else { continue }

            let ipaFileURL = URL.documentsDirectory.appending(path: asset.name)

            if fileSize(ipaFileURL) == asset.size {
                log.notice("using cached IPA: \(asset.name, privacy: .public)")
                status("Using cached \(asset.name)")
                return ipaFileURL
            }

            log.notice("downloading \(asset.name, privacy: .public)")
            let label = "Downloading \(asset.name) (\(asset.size / 1_000_000) MB)"
            status(label)

            let part = ipaFileURL.appendingPathExtension("part")
            let tracker = DownloadTracker()
            let size = Double(asset.size)
            let poller = Task {
                while !Task.isCancelled {
                    progress(min(Double(tracker.received) / size, 1))
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            defer {
                poller.cancel()
                progress(nil)
            }
            do {
                try await parallelDownload(downloadURL, size: asset.size, to: part, tracker: tracker)
            } catch {
                log.error("parallel download failed, single stream: \(error.localizedDescription, privacy: .public)")
                status("\(label) (single stream)")
                tracker.reset()
                try? FileManager.default.removeItem(at: part)
                let (tempFile, _) = try await URLSession.shared.download(from: downloadURL, delegate: tracker)
                try FileManager.default.moveItem(at: tempFile, to: part)
            }

            try? FileManager.default.removeItem(at: ipaFileURL)
            try FileManager.default.moveItem(at: part, to: ipaFileURL)
            log.notice("Downloaded Roblox IPA to: \(ipaFileURL.path, privacy: .public)")

            for old in cachedIpas() where old.lastPathComponent != ipaFileURL.lastPathComponent {
                try? FileManager.default.removeItem(at: old)
                log.notice("removed old IPA: \(old.lastPathComponent, privacy: .public)")
            }
            return ipaFileURL
        }
        log.error("no .ipa asset in latest release")
    } catch {
        log.error("Failed: \(error.localizedDescription, privacy: .public)")
        status("Couldn't check latest Roblox: \(error.localizedDescription)")
    }

    if let cached = cachedIpas().first {
        log.notice("falling back to cached IPA: \(cached.lastPathComponent, privacy: .public)")
        status("Using cached \(cached.lastPathComponent)")
        return cached
    }
    status("Failed: no Roblox IPA downloaded or cached")
    return nil
}

func patchRoblox(
    modZips: [URL], status: @escaping PatchStatus = { _ in },
    downloadProgress: @escaping @Sendable (Double?) -> Void = { _ in }
) async -> URL? {
    guard let ipaURL = await downloadRobloxIpa(status: status, progress: downloadProgress)
    else { return nil }

    return await Task.detached(priority: .userInitiated) { () -> URL? in
        do {
            log.notice("patching with \(modZips.count) mod(s)")
            let out = URL.documentsDirectory.appending(path: "Roblox-patched.ipa")
            let start = Date()
            let files = try IpaPatcher.patch(ipa: ipaURL, mods: modZips, output: out, status: status)
            let secs = Date().timeIntervalSince(start)
            log.notice("patched \(files) file(s) in \(secs, format: .fixed(precision: 2))s")
            log.notice("patched IPA: \(out.path, privacy: .public)")
            status("Done: \(files) mod file(s) in \(String(format: "%.1f", secs))s")
            return out
        } catch {
            log.error("patch failed: \(error.localizedDescription, privacy: .public)")
            status("Failed: \(error.localizedDescription)")
            return nil
        }
    }.value
}

private actor ChunkWriter {
    private let handle: FileHandle
    private var finished = 0

    init(_ url: URL, size: Int) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(size))
    }

    /// Copies a downloaded chunk to `offset`.
    func write(_ chunk: URL, at offset: Int) throws {
        defer { try? FileManager.default.removeItem(at: chunk) }
        try handle.seek(toOffset: UInt64(offset))
        try handle.write(contentsOf: Data(contentsOf: chunk, options: .mappedIfSafe))
    }

    func close() { try? handle.close() }
}


final class DownloadTracker: NSObject, URLSessionTaskDelegate, Sendable {
    private let tasks = Mutex<[URLSessionTask]>([])

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        tasks.withLock { $0.append(task) }
    }

    var received: Int64 { tasks.withLock { $0.reduce(0) { $0 + $1.countOfBytesReceived } } }

    func reset() { tasks.withLock { $0.removeAll() } }
}


func parallelDownload(
    _ url: URL, size: Int, to dest: URL, parts: Int = 8, tracker: DownloadTracker
) async throws {
    guard size > 0 else { throw ZipError("unknown size") }

    var head = URLRequest(url: url)
    head.httpMethod = "HEAD"
    let (_, headResponse) = try await URLSession.shared.data(for: head)
    let target = headResponse.url ?? url

    let writer = try ChunkWriter(dest, size: size)
    let chunk = (size + parts - 1) / parts
    let ranges = stride(from: 0, to: size, by: chunk).map { ($0, min($0 + chunk, size) - 1) }

    do {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (start, end) in ranges {
                group.addTask {
                    var req = URLRequest(url: target)
                    req.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
                    let (file, response) = try await URLSession.shared.download(for: req, delegate: tracker)
                    guard (response as? HTTPURLResponse)?.statusCode == 206,
                        response.expectedContentLength == Int64(end - start + 1)
                    else {
                        try? FileManager.default.removeItem(at: file)
                        throw ZipError("server ignored Range request")
                    }
                    try await writer.write(file, at: start)
                }
            }
            try await group.waitForAll()
        }
    } catch {
        await writer.close()
        throw error
    }
    await writer.close()
}
