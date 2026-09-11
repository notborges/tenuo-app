import Foundation

enum HIDMappingParser {
    static func parse(_ data: Data) -> [[String: Any]]? {
        guard
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }

        if text == "(null)" { return [] }

        var format = PropertyListSerialization.PropertyListFormat.openStep
        guard
            let value = try? PropertyListSerialization.propertyList(
                from: Data(text.utf8), options: [], format: &format),
            let values = value as? [Any],
            values.allSatisfy({ $0 is [String: Any] })
        else { return nil }

        return values.compactMap { $0 as? [String: Any] }
    }
}
