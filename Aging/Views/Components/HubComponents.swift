import SwiftUI

/// The visual vocabulary the app was missing.
///
/// Before this, every capability in the app was a grey list row with a small
/// grey glyph, and a real user's first reaction was that it was not clear what
/// the app did. These are the pieces that answer that: a tile that names a
/// feature *and says what it is for*, a stat that can be read across a kitchen,
/// and a checklist that admits there is more to set up.
///
/// Sizing here is deliberate. Body text stays at or above `AppTheme
/// .minimumBodySize`, tap targets stay at or above 44pt, and everything scales
/// with Dynamic Type: the audience is mostly over fifty and often reading in a
/// waiting room.

// MARK: - Feature tile

/// One capability, as a card: coloured glyph, name, what it is for, and how
/// much is in it.
struct FeatureTile: View {
    let feature: CareFeature
    let detail: String
    /// An empty feature reads as an invitation rather than as a record, so the
    /// count line is dimmed and the icon loses its fill.
    let isEmpty: Bool

    /// Split out of `body` on purpose: with the ternaries inline the whole tile
    /// became an expression the type checker gave up on.
    private var tint: Color { isEmpty ? .secondary : feature.color }

    private var glyph: some View {
        Image(systemName: feature.symbol)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(
                tint.opacity(isEmpty ? 0.10 : 0.14),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                glyph
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(feature.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }

            // Pins the count to the bottom of the card, which combined with the
            // stretched frame below keeps two tiles in a row the same height
            // whether one of them wraps to a second line or not.
            Spacer(minLength: 4)

            Text(detail)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isEmpty ? .tertiary : .secondary)
                .lineLimit(2)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(feature.title). \(feature.blurb). \(detail)")
    }
}

// MARK: - Stat

/// One number worth acting on, big enough to read at arm's length.
struct StatTile: View {
    let value: String
    let label: String
    let symbol: String
    let tint: Color
    /// Draws attention only when there is something outstanding. A screen where
    /// everything is orange says nothing.
    var isAttention: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isAttention ? tint : .secondary)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(isAttention ? tint : .primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

// MARK: - Quick action

/// A one-tap way into a feature from the Today tab, so the app's range is
/// visible on the screen people actually open, not two taps down.
///
/// Shares the row's width rather than claiming a fixed 72pt. At a fixed width
/// the labels of adjacent chips butted into each other and the row ran off the
/// right edge of the screen, so the two chips a caregiver had never scrolled to
/// were, in effect, not in the app.
/// Sized for the audience rather than for density. The glyph is a 56pt filled
/// disc and the label is body weight, because the first complaint about this
/// screen from someone actually in the target age band was that the controls
/// were small and it was not obvious they were controls. A card behind the
/// whole chip is what makes it read as a button rather than as decoration.
struct QuickActionChip: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 56, height: 56)
                .background(tint.opacity(0.16), in: Circle())
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .top)
        .padding(.vertical, 12)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Big navigation card

/// A full-width card that goes somewhere, at the size the rest of this screen
/// now works at.
///
/// The emergency card and the full record used to be two ordinary list rows
/// with a small grey glyph, which put the two most important destinations in
/// the app at the same visual weight as a settings toggle.
struct BigNavCard: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Setup progress

/// "You have set up 3 of 6." The single most direct answer to "what can this
/// thing do": it lists the things that exist and marks off the ones already
/// done, and it disappears once there is nothing left to say.
struct SetupProgressCard: View {
    let personLabel: String
    let steps: [SetupStep]
    let onSelect: (SetupStep) -> Void
    /// Wave one row away for good. Per row rather than per card, because the
    /// reasons are per row: "I am the only one looking after him" is a fair
    /// answer to inviting a sibling and a terrible reason to lose the other
    /// five.
    let onDismissStep: (SetupStep) -> Void
    let onHide: () -> Void

    /// Collapsed to three by default: at the top of Today, six rows is a wall
    /// rather than a nudge. Expanding is what makes every row reachable, which
    /// per-row dismissal needs it to be.
    @State private var isExpanded = false

    private var done: Int { SetupChecklist.completed(steps) }

    private var undone: [SetupStep] { steps.filter { !$0.isDone } }

    private var remaining: [SetupStep] {
        isExpanded ? undone : Array(undone.prefix(3))
    }

    private var hiddenCount: Int { undone.count - remaining.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Set up \(personLabel)'s record")
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.leading)
                    Text("\(done) of \(steps.count) done")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                Button("Hide", action: onHide)
                    .font(.body)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Hide the whole setup list")
            }

            ProgressView(value: Double(done), total: Double(max(steps.count, 1)))
                .tint(.accentColor)

            VStack(spacing: 0) {
                ForEach(Array(remaining.enumerated()), id: \.element.id) { index, step in
                    HStack(spacing: 4) {
                        Button {
                            onSelect(step)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: step.symbol)
                                    .font(.system(size: 19, weight: .semibold))
                                    .foregroundStyle(.tint)
                                    .frame(width: 40, height: 40)
                                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(step.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(step.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .multilineTextAlignment(.leading)

                                Spacer(minLength: 0)

                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // A separate 44pt target, not a swipe: this card is not
                        // a list row, and a gesture nobody can see is not a way
                        // to dismiss anything.
                        Button {
                            onDismissStep(step)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss \(step.title)")
                    }

                    if index < remaining.count - 1 {
                        Divider()
                    }
                }
            }

            if hiddenCount > 0 || isExpanded {
                Button {
                    isExpanded.toggle()
                } label: {
                    Text(isExpanded ? "Show fewer" : "Show \(hiddenCount) more")
                        .font(.body.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityIdentifier("setup-card.expand")
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }
}

// MARK: - Emergency card banner

/// The emergency card is the thing this app is *for* on the worst day, and it
/// was previously the last row of a long list. It gets a banner of its own.
struct EmergencyCardBanner: View {
    let personLabel: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "cross.case.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Color(red: 0.80, green: 0.25, blue: 0.28), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Emergency card")
                    .font(.headline)
                Text("One page for the ER: \(personLabel)'s meds, allergies, contacts. Works with no signal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Emergency card. One page for the emergency room.")
    }
}

// MARK: - Person header

/// Who this screen is about, plus the two or three numbers worth acting on.
struct PersonHeaderCard: View {
    let person: Person
    let dosesTaken: Int
    let dosesTotal: Int
    let tasksDue: Int
    let runningLow: Int

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(person.color.opacity(0.18))
                    Text(person.initials)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(person.color)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text(person.name)
                        .font(.title3.weight(.semibold))
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                StatTile(
                    value: dosesTotal == 0 ? "—" : "\(dosesTaken)/\(dosesTotal)",
                    label: "Doses today",
                    symbol: "pills.fill",
                    tint: .accentColor
                )
                StatTile(
                    value: "\(tasksDue)",
                    label: tasksDue == 1 ? "Task due" : "Tasks due",
                    symbol: "checklist",
                    tint: .orange,
                    isAttention: tasksDue > 0
                )
                StatTile(
                    value: "\(runningLow)",
                    label: "Running low",
                    symbol: "exclamationmark.triangle.fill",
                    tint: .orange,
                    isAttention: runningLow > 0
                )
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if !person.relationship.isEmpty { parts.append(person.relationship) }
        if let age = person.age { parts.append("\(age)") }
        return parts.joined(separator: " · ")
    }
}

#Preview("Tiles") {
    ScrollView {
        VStack(spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                FeatureTile(feature: .medications, detail: "4 medications", isEmpty: false)
                FeatureTile(feature: .vitals, detail: "None yet", isEmpty: true)
            }
            EmergencyCardBanner(personLabel: "Mom")
            SetupProgressCard(
                personLabel: "Mom",
                steps: [
                    SetupStep(kind: .addMedication, title: "Add a medication", detail: "Times, strength and what it's for", symbol: "pills.fill", isDone: true),
                    SetupStep(kind: .doseReminders, title: "Turn on dose reminders", detail: "This phone buzzes at each dose time", symbol: "bell.badge.fill", isDone: false),
                    SetupStep(kind: .inviteFamily, title: "Invite the family", detail: "Siblings see the same list, free", symbol: "person.2.fill", isDone: false)
                ],
                onSelect: { _ in },
                onDismissStep: { _ in },
                onHide: {}
            )
            BigNavCard(
                title: "Emergency card",
                detail: "One page for the ER. Works with no signal.",
                symbol: "cross.case.fill",
                tint: .red
            )
        }
        .padding()
    }
    .background(Color(uiColor: .systemGroupedBackground))
}
