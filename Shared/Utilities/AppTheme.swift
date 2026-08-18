import SwiftUI

enum AppTheme {
    /// Each person gets a stable color so a med, a visit and a vital all read as
    /// belonging to the same someone at a glance.
    static let personColors: [Color] = [
        Color(red: 0.20, green: 0.47, blue: 0.85),
        Color(red: 0.85, green: 0.37, blue: 0.31),
        Color(red: 0.30, green: 0.64, blue: 0.44),
        Color(red: 0.60, green: 0.38, blue: 0.76),
        Color(red: 0.90, green: 0.60, blue: 0.20),
        Color(red: 0.25, green: 0.63, blue: 0.68)
    ]

    static func color(forPersonIndex index: Int) -> Color {
        guard !personColors.isEmpty else { return .accentColor }
        return personColors[((index % personColors.count) + personColors.count) % personColors.count]
    }

    /// One colour per feature, so a feature is recognisable by its icon before
    /// its label is read. Ordered to match `CareFeature.colorIndex`.
    ///
    /// These are the icon tints only, never a text colour or a fill behind
    /// text: at 12% opacity behind a saturated glyph they clear contrast in
    /// both appearances, which is the constraint that matters for an audience
    /// mostly over fifty.
    static let featureColors: [Color] = [
        Color(red: 0.20, green: 0.47, blue: 0.85),  // medications
        Color(red: 0.30, green: 0.62, blue: 0.42),  // tasks
        Color(red: 0.85, green: 0.30, blue: 0.36),  // vitals
        Color(red: 0.25, green: 0.60, blue: 0.68),  // visits
        Color(red: 0.45, green: 0.45, blue: 0.80),  // providers
        Color(red: 0.88, green: 0.55, blue: 0.18),  // incidents
        Color(red: 0.48, green: 0.48, blue: 0.52),  // timeline
        Color(red: 0.72, green: 0.32, blue: 0.62),  // health details
        Color(red: 0.22, green: 0.55, blue: 0.60),  // contacts
        // Not the brown it started as: under `hand.wave.fill` a warm brown
        // reads as a skin tone rather than as this app's colour for check-in.
        Color(red: 0.47, green: 0.38, blue: 0.82),  // check-in
        Color(red: 0.62, green: 0.52, blue: 0.22),  // notes
        Color(red: 0.18, green: 0.52, blue: 0.45)   // bills
    ]

    static func color(forFeatureIndex index: Int) -> Color {
        guard !featureColors.isEmpty else { return .accentColor }
        return featureColors[((index % featureColors.count) + featureColors.count) % featureColors.count]
    }

    /// Older eyes are a real constraint here, and so is a caregiver reading a screen
    /// in a waiting room. Body text does not go below this.
    static let minimumBodySize: CGFloat = 17

    static let cardCornerRadius: CGFloat = 14
}

extension CareFeature {
    var color: Color {
        AppTheme.color(forFeatureIndex: colorIndex)
    }
}

extension Person {
    var color: Color {
        AppTheme.color(forPersonIndex: colorIndex)
    }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}
