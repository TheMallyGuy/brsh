import Foundation

enum FFlagStore {
    static let file = URL.documentsDirectory.appending(path: "fflags.json")
    static let defaultJSON = """
        {

        }
        """

    static func load() -> String {
        (try? String(contentsOf: file, encoding: .utf8)) ?? defaultJSON
    }

    static func save(_ text: String) -> String? {
        guard let data = text.data(using: .utf8),
            (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
        else { return "Not a valid JSON object" }
        do {
            try data.write(to: file, options: .atomic)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

enum FFlagPreset {
    private static let telemetryFlagsTrue = [  // verity
        "FFlagDebugDisableTelemetryEphemeralCounter",
        "FFlagDebugDisableTelemetryEphemeralStat",
        "FFlagDebugDisableTelemetryEventIngest",
        "FFlagDebugDisableTelemetryPoint",
    ]

    private static let telemetryFlagsFalse = [  // falsity
        "FFlagEnableClickToMoveUsageTelemetry2",
        "FFlagAvatarSwitcherCounters",
        "DFFlagVoiceChatSendHttpErrorsTelemetry",  // voice chat errors
    ]

    private static let lightingFlags = [
        "FFlagDisableShadows",
        "FFlagDisableBloom",
        "FFlagDisablePostFx",
        "FFlagSuppressSunRays",
    ]

    private static let parallelLuaWorkers = "FIntDebugForceParallelLuaWorkerCount"

    private static let voxelizerFlag = "DFFlagDebugPauseVoxelizer"

    private static let skyGrayFlag = "FFlagDebugSkyGray"

    private static let msaaFlag = "FIntDebugForceMSAASamples"

    private static func parseConfig(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            print("Parse failed: \(error)")
            return nil
        }
    }

    static func noTelemetry() -> Bool {
        let FFlagsString = FFlagStore.load()
        guard let FFlags = parseConfig(FFlagsString) else { return false }
        for flag in telemetryFlagsTrue {
            if FFlags[flag] as? String != "True" {  // these are all trues
                return false
            }
        }
        for flag in telemetryFlagsFalse {
            if FFlags[flag] as? String != "False" {
                return false
            }
        }
        return true
    }

    static func lighting() -> Bool {
        let FFlagsString = FFlagStore.load()
        guard let FFlags = parseConfig(FFlagsString) else { return false }
        for flag in lightingFlags {
            if FFlags[flag] as? String != "True" {  // these are all trues too
                return false
            }
        }
        return true
    }

    // TODO: turn these into reusable functions
    static func msaa() -> Int? {
        guard let fFlags = parseConfig(FFlagStore.load()) else { return 0 }

        let value = fFlags[msaaFlag]
        if let n = value as? Int { return n }
        if let s = value as? String { return Int(s) }  // handles string too

        return 0
    }

    static func parallelWorkers() -> Int? {
        guard let fFlags = parseConfig(FFlagStore.load()) else { return 8 }

        let value = fFlags[parallelLuaWorkers]
        if let n = value as? Int { return n }
        if let s = value as? String { return Int(s) }  // handles string too

        return 8
    }

    static func pauseVoxelizer() -> Bool? {
        guard let fFlags = parseConfig(FFlagStore.load()) else { return false }

        let value = fFlags[voxelizerFlag]
        if let n = value as? Bool { return n }

        return false
    }

    static func skyGray() -> Bool? {
        guard let fFlags = parseConfig(FFlagStore.load()) else { return false }

        let value = fFlags[skyGrayFlag]
        if let n = value as? Bool { return n }

        return false
    }

    static func apply(
        noTelemetry: Bool, lighting: Bool, pauseVoxelizer: Bool, msaa: Int, skyGray: Bool,
        pararellWorkers: Int
    ) -> String? {  // burger code
        guard var flags: [String: Any] = parseConfig(FFlagStore.load()) else {
            return "Current flags file isn't valid JSON"
        }

        for flag in telemetryFlagsTrue { flags[flag] = noTelemetry ? "True" : nil }
        for flag in telemetryFlagsFalse { flags[flag] = noTelemetry ? "False" : nil }
        for flag in lightingFlags { flags[flag] = lighting ? "True" : nil }

        flags[voxelizerFlag] = pauseVoxelizer ? "True" : nil
        flags[skyGrayFlag] = skyGray ? "True" : nil
        flags[parallelLuaWorkers] = Int(pararellWorkers) > 8 ? Int(pararellWorkers) : nil // 8 is roblox's default i think
        flags[msaaFlag] = msaa > 0 ? Int(msaa) : nil  // 0 = auto, so remove the flag

        guard
            let data = try? JSONSerialization.data(
                withJSONObject: flags, options: [.prettyPrinted, .sortedKeys]),
            let json = String(data: data, encoding: .utf8)
        else { return "Couldn't encode flags" }

        return FFlagStore.save(json)
    }
}
