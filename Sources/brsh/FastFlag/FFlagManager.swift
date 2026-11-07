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