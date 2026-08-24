import Foundation

/// How a row from PostgREST turns into a `Date`.
///
/// supabase-swift ships one date strategy and it only parses a full ISO8601
/// timestamp. PostgREST serialises a `date` column as a bare "1939-07-13",
/// which fails it, and because a decoding error fails the whole response rather
/// than the one field, a single birthday meant a joining phone downloaded no
/// people at all and no medications either. Migration 0021 took the `date`
/// columns out of the schema; this is the other half, so the next one somebody
/// adds is a formatting detail rather than an outage.
///
/// Only ever more permissive than the SDK's own decoder: every string it
/// accepts, this accepts, and the extra shapes are the ones Postgres actually
/// emits.
enum PostgrestCoding {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = parse(raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid date format: \(raw)"
                )
            }
            return date
        }
        return decoder
    }

    /// A bare day is read at **noon UTC**, matching how 0021 converted the
    /// columns it replaced. Midnight read back through a US calendar is the
    /// evening before, which moves a birthday to the wrong day.
    static func parse(_ raw: String) -> Date? {
        if let date = try? Date(raw, strategy: iso(fractionalSeconds: true)) { return date }
        if let date = try? Date(raw, strategy: iso(fractionalSeconds: false)) { return date }
        if let day = try? Date(raw, strategy: .iso8601.year().month().day()) {
            return day.addingTimeInterval(12 * 60 * 60)
        }
        return nil
    }

    private static func iso(fractionalSeconds: Bool) -> Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle()
            .year().month().day()
            .dateTimeSeparator(.standard)
            .time(includingFractionalSeconds: fractionalSeconds)
    }
}
