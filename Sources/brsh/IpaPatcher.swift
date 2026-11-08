import Foundation
#if canImport(Compression)
import Compression
#else
import CZlib  // Linux test harness only
#endif

typealias PatchStatus = @Sendable (String) -> Void

/// Applies mod zips to a Roblox IPA without recompressing it.
/// Unchanged entries are copied as raw compressed bytes; mod files are added stored (uncompressed).
enum IpaPatcher {
    static let modRoot = "Payload/Roblox.app/Frameworks/RobloxLib.framework/"
    /// Top-level folders inside RobloxLib.framework that mods target.
    static let gameDirs: Set<String> = ["content", "ExtraContent", "shaders", "ssl", "ios"]

    /// Patches `ipa` with `mods` (in order; later mods win) into `output`. Returns number of mod files written.
    @discardableResult
    static func patch(ipa: URL, mods: [URL], output: URL, status: PatchStatus = { _ in }) throws -> Int {
        var replacements: [String: Data] = [:]
        var order: [String] = []
        for (n, mod) in mods.enumerated() {
            status("Reading mod \(n + 1)/\(mods.count): \(mod.deletingPathExtension().lastPathComponent)")
            for (rel, data) in try modFiles(mod) {
                let path = modRoot + rel
                if replacements[path] == nil { order.append(path) }
                replacements[path] = data
            }
        }

        let src = try ZipReader(url: ipa)
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let out = try FileHandle(forWritingTo: output)
        defer { try? out.close() }

        var pos = 0
        var central = Data()
        var count = 0
        var lastPct = -1
        func report(_ label: String, _ done: Int, of total: Int) {
            let pct = done * 100 / max(total, 1)
            if pct != lastPct { lastPct = pct; status("\(label) \(pct)%") }
        }

        // 1. copy unchanged entries byte-for-byte (local header + data + optional descriptor)
        let sorted = src.entries.sorted { $0.localOffset < $1.localOffset }
        for (i, entry) in sorted.enumerated() where replacements[entry.name] == nil {
            let end = i + 1 < sorted.count ? sorted[i + 1].localOffset : src.centralOffset
            try src.copy(from: entry.localOffset, count: end - entry.localOffset, to: out)
            var record = entry.central
            record.replaceSubrange(record.startIndex + 42 ..< record.startIndex + 46, with: le32(pos))
            central.append(record)
            pos += end - entry.localOffset
            count += 1
            report("Copying Roblox files", entry.localOffset, of: src.centralOffset)
        }

        // 2. append mod files, stored
        lastPct = -1
        for (k, path) in order.enumerated() {
            report("Adding \(order.count) mod files", k + 1, of: order.count)
            let data = replacements[path]!
            let name = Data(path.utf8)
            let crc = crc32(data)

            var local = Data()
            local += le32(0x0403_4B50) + le16(20) + le16(0x0800) + le16(0)  // sig, version, utf8 flag, stored
            local += le16(0) + le16(0x21) + le32(crc)                         // time, date (1980-01-01), crc
            local += le32(data.count) + le32(data.count) + le16(name.count) + le16(0)
            local += name
            out.write(local)
            out.write(data)

            var record = Data()
            record += le32(0x0201_4B50) + le16(0x031E) + le16(20) + le16(0x0800) + le16(0)
            record += le16(0) + le16(0x21) + le32(crc) + le32(data.count) + le32(data.count)
            record += le16(name.count) + le16(0) + le16(0) + le16(0) + le16(0)
            record += le32(0o100644 << 16) + le32(pos) + name                 // rw-r--r-- file
            central.append(record)

            pos += local.count + data.count
            count += 1
        }

        guard count <= 0xFFFF, pos + central.count <= 0xFFFF_FFFF else {
            throw ZipError("output needs zip64 (too large)")
        }

        // 3. central directory + end record
        status("Writing IPA index")
        out.write(central)
        var eocd = Data()
        eocd += le32(0x0605_4B50) + le16(0) + le16(0) + le16(count) + le16(count)
        eocd += le32(central.count) + le32(pos) + le16(0)
        out.write(eocd)
        return order.count
    }

    /// Reads a mod zip into (path relative to RobloxLib.framework, bytes).
    /// Skips folders and macOS junk, strips wrapper folders (e.g. "Fishstrap/content/..."),
    /// and drops a root info.json (mod metadata).
    static func modFiles(_ url: URL) throws -> [(String, Data)] {
        let zip = try ZipReader(url: url)
        var files = try zip.entries
            .filter { !$0.name.hasSuffix("/") && !$0.name.contains("__MACOSX/") && !$0.name.hasSuffix(".DS_Store") }
            .map { ($0.name, try zip.data(of: $0)) }

        while true {
            let roots = Set(files.map { $0.0.contains("/") ? String($0.0.split(separator: "/")[0]) : "" })
            guard roots.count == 1, let root = roots.first, !root.isEmpty, !gameDirs.contains(root) else { break }
            files = files.map { (String($0.0.dropFirst(root.count + 1)), $0.1) }
        }
        return files.filter { $0.0 != "info.json" }
    }
}

// MARK: - Zip reading

struct ZipError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

struct ZipEntry {
    let name: String
    let central: Data  // full central directory record
    let localOffset: Int
    let compressedSize: Int
    let uncompressedSize: Int
    let method: Int
}

final class ZipReader {
    let handle: FileHandle
    let entries: [ZipEntry]
    let centralOffset: Int

    init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        let size = Int(try handle.seekToEnd())
        let tailCount = min(size, 22 + 0xFFFF)
        let tail = try Self.read(handle, size - tailCount, tailCount)

        var eocd = tail.count - 22
        while eocd >= 0, tail.u32(eocd) != 0x0605_4B50 { eocd -= 1 }
        guard eocd >= 0 else { throw ZipError("no end-of-central-directory record") }

        let count = tail.u16(eocd + 10), cdSize = tail.u32(eocd + 12), cdOffset = tail.u32(eocd + 16)
        guard count != 0xFFFF, cdOffset != 0xFFFF_FFFF else { throw ZipError("zip64 not supported") }
        centralOffset = cdOffset

        let cd = try Self.read(handle, cdOffset, cdSize)
        var list: [ZipEntry] = []
        var p = 0
        for _ in 0 ..< count {
            guard p + 46 <= cd.count, cd.u32(p) == 0x0201_4B50 else { throw ZipError("bad central directory") }
            let nameLen = cd.u16(p + 28), extraLen = cd.u16(p + 30), commentLen = cd.u16(p + 32)
            let len = 46 + nameLen + extraLen + commentLen
            let name = String(decoding: cd.subdata(in: p + 46 ..< p + 46 + nameLen), as: UTF8.self)
            list.append(ZipEntry(
                name: name, central: cd.subdata(in: p ..< p + len), localOffset: cd.u32(p + 42),
                compressedSize: cd.u32(p + 20), uncompressedSize: cd.u32(p + 24), method: cd.u16(p + 10)))
            p += len
        }
        entries = list
    }

    deinit { try? handle.close() }

    /// Decompressed bytes of an entry.
    func data(of e: ZipEntry) throws -> Data {
        let header = try Self.read(handle, e.localOffset, 30)
        guard header.u32(0) == 0x0403_4B50 else { throw ZipError("bad local header: \(e.name)") }
        let start = e.localOffset + 30 + header.u16(26) + header.u16(28)
        let raw = try Self.read(handle, start, e.compressedSize)
        switch e.method {
        case 0: return raw
        case 8: return try inflate(raw, size: e.uncompressedSize)
        default: throw ZipError("unsupported compression \(e.method): \(e.name)")
        }
    }

    /// Streams `count` raw bytes starting at `offset` into `out`.
    func copy(from offset: Int, count: Int, to out: FileHandle) throws {
        try handle.seek(toOffset: UInt64(offset))
        var left = count
        while left > 0 {
            let chunk = try handle.read(upToCount: min(left, 1 << 20)) ?? Data()
            guard !chunk.isEmpty else { throw ZipError("unexpected end of file") }
            out.write(chunk)
            left -= chunk.count
        }
    }

    static func read(_ h: FileHandle, _ offset: Int, _ count: Int) throws -> Data {
        try h.seek(toOffset: UInt64(offset))
        let d = try h.read(upToCount: count) ?? Data()
        guard d.count == count else { throw ZipError("short read") }
        return d
    }
}

// MARK: - Helpers

extension Data {
    func u16(_ i: Int) -> Int { Int(self[startIndex + i]) | Int(self[startIndex + i + 1]) << 8 }
    func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
}

private func le16(_ v: Int) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)]) }
private func le32(_ v: Int) -> Data { le16(v & 0xFFFF) + le16(v >> 16 & 0xFFFF) }

private let crcTable: [UInt32] = (0 ..< 256).map { n -> UInt32 in
    var c = UInt32(n)
    for _ in 0 ..< 8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
    return c
}

func crc32(_ data: Data) -> Int {
    var c: UInt32 = 0xFFFF_FFFF
    for b in data { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
    return Int(c ^ 0xFFFF_FFFF)
}

/// Raw DEFLATE (zip method 8) decode.
func inflate(_ data: Data, size: Int) throws -> Data {
    if size == 0 { return Data() }
    var out = Data(count: size)
    #if canImport(Compression)
    let n = out.withUnsafeMutableBytes { dst in
        data.withUnsafeBytes { src in
            compression_decode_buffer(
                dst.bindMemory(to: UInt8.self).baseAddress!, size,
                src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
        }
    }
    #else
    var stream = z_stream()
    inflateInit2_(&stream, -15, zlibVersion(), Int32(MemoryLayout<z_stream>.size))
    defer { inflateEnd(&stream) }
    var input = [UInt8](data)
    let n = out.withUnsafeMutableBytes { dst -> Int in
        input.withUnsafeMutableBytes { src -> Int in
            stream.next_in = src.bindMemory(to: Bytef.self).baseAddress
            stream.avail_in = uInt(data.count)
            stream.next_out = dst.bindMemory(to: Bytef.self).baseAddress
            stream.avail_out = uInt(size)
            inflate(&stream, Z_FINISH)
            return Int(stream.total_out)
        }
    }
    #endif
    guard n == size else { throw ZipError("inflate failed (\(n)/\(size) bytes)") }
    return out
}
