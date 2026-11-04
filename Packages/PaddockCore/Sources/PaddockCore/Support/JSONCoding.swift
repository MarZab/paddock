import Foundation

/// Decoding shared by every sbx and llmman model: snake_case keys and ISO 8601 dates
/// with or without fractional seconds and with `Z` or a numeric offset.
public enum JSONCoding {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = parseDate(text) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "not an ISO 8601 date: \(text)")
        }
        return decoder
    }

    public static func parseDate(_ text: String) -> Date? {
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let plain = Date.ISO8601FormatStyle()
        return (try? withFraction.parse(text)) ?? (try? plain.parse(text))
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder().decode(type, from: data)
    }
}
