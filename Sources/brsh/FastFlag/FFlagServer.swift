import Foundation
import Network
import UIKit

enum FFlagStore {
    static let file = URL.documentsDirectory.appending(path: "fflags.json")
    static let defaultJSON = """
        {
          "DFIntTaskSchedulerTargetFps": "240",
          "FIntFRMMinGrassDistance": "100",
          "FFlagDebugSkyGray": "true",
          "DFFlagDisableDPIScale": "true"
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

final class FFlagServer: @unchecked Sendable {
    static let shared = FFlagServer()
    static let port: NWEndpoint.Port = 8777

    private let queue = DispatchQueue(label: "brsh.fflagserver")
    private var listener: NWListener?

    func start() {
        queue.async { [self] in
            guard listener == nil else { return }
            do {
                let params = NWParameters.tcp
                params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: Self.port)  // loopback only
                params.allowLocalEndpointReuse = true

                let l = try NWListener(using: params)
                l.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
                l.stateUpdateHandler = { [weak self] state in
                    log.notice("fflag server: \(String(describing: state), privacy: .public)")
                    if case .failed = state { self?.restart() }
                }

                l.start(queue: queue)
                listener = l
            } catch {
                log.error("fflag server failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func restart() {
        queue.async { [self] in
            listener?.cancel()
            listener = nil
            start()
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""

            let (status, body): (String, String) =
                path == "/fflags.json"
                ? ("200 OK", FFlagStore.load()) : ("404 Not Found", "not found")
            log.notice("fflag server: \(path, privacy: .public) -> \(status, privacy: .public)")

            let bytes = Data(body.utf8)
            let head =
                "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(bytes.count)\r\nConnection: close\r\n\r\n"
            conn.send(
                content: Data(head.utf8) + bytes,
                completion: .contentProcessed { _ in conn.cancel() })
        }
    }

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    @MainActor
    func enteredBackground() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "fflag server") {
            [weak self] in
            self?.endBackground()
        }
        log.notice("fflag server: background grace started")
    }

    @MainActor
    func endBackground() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
