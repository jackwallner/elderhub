import SwiftData
import SwiftUI

/// Generating a code and getting it to the person.
///
/// Two kinds of invite, and the distinction is not cosmetic. A caregiver invite
/// adds a sibling who sees everyone. A subject invite links an account to one
/// existing recipient row, so the parent joining is joined to the profile the
/// family already built for her rather than arriving unattached with no history.
struct InviteSheet: View {
    let people: [Person]

    @Environment(GroupService.self) private var groups
    @Environment(\.dismiss) private var dismiss

    @State private var kind: Kind = .caregiver
    @State private var recipientID: UUID?
    @State private var emailAddress = ""
    @State private var code: String?
    @State private var isWorking = false
    @State private var errorMessage: String?

    enum Kind: String, CaseIterable, Identifiable {
        case caregiver, subject
        var id: String { rawValue }

        var label: String {
            switch self {
            case .caregiver: return "Another caregiver"
            case .subject: return "The person being looked after"
            }
        }

        var detail: String {
            switch self {
            case .caregiver:
                return "A brother, sister or partner. They see and edit everyone in the family."
            case .subject:
                return "They see only their own list, mark their own doses, and press their own check-in button."
            }
        }
    }

    /// Only people with no account attached can be linked by a subject invite.
    private var linkable: [Person] {
        people.filter { $0.linkedUserID == nil }
    }

    private var selectedPersonName: String? {
        guard let recipientID else { return nil }
        return people.first(where: { $0.id == recipientID })?.displayLabel
    }

    private var normalizedEmail: String {
        emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Empty is valid: the email is optional, and a code read out over the
    /// phone is a first-class way to deliver one. Anything else has to satisfy
    /// the same rule the server does, or "Create" fails with a raw 22023.
    private var emailIsValid: Bool {
        normalizedEmail.isEmpty || InviteLink.isValidEmail(normalizedEmail)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let code {
                    codeSection(code)
                } else {
                    pickerSection
                    if kind == .subject { recipientSection }
                    emailSection
                    generateSection
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(code == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
        }
    }

    private var pickerSection: some View {
        Section {
            ForEach(Kind.allCases) { option in
                Button {
                    kind = option
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label)
                                .font(.body.weight(.medium))
                            Text(option.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if kind == option {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Who are you inviting?")
        }
    }

    private var recipientSection: some View {
        Section {
            if linkable.isEmpty {
                Text("Everyone you track already has an account linked.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Their record", selection: $recipientID) {
                    Text("Choose").tag(UUID?.none)
                    ForEach(linkable) { person in
                        Text(person.name).tag(UUID?.some(person.id))
                    }
                }
            }
        } header: {
            Text("Link them to")
        } footer: {
            Text("They join the record you already built, so the medication history carries over.")
        }
    }

    private var generateSection: some View {
        Section {
            Button {
                Task { await generate() }
            } label: {
                if isWorking {
                    ProgressView()
                } else {
                    Text("Create invitation")
                }
            }
            .disabled(
                isWorking
                || !emailIsValid
                || (kind == .subject && recipientID == nil)
            )
        }
    }

    private var emailSection: some View {
        Section {
            TextField("Email address", text: $emailAddress)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !emailIsValid {
                Text("Enter a valid email address.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Send to")
        } footer: {
            // Elderhub has no mail server of its own, so this address is a
            // label on the invitation and a prefilled composer, not a send. The
            // wording has to say so here rather than after the fact, or "Create"
            // reads as "Send" and the invitation sits in a list nobody was told
            // about.
            Text("Optional. Elderhub does not send the email for you: it writes it and hands it to Mail, so you press send. You can also share the link or read the code out.")
        }
    }

    private func codeSection(_ code: String) -> some View {
        Section {
            Text(code)
                .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .textSelection(.enabled)

            if let emailURL = InviteMessage.emailURL(
                address: normalizedEmail,
                code: code,
                role: kind == .subject ? .subject : .caregiver,
                personName: selectedPersonName
            ) {
                Link(destination: emailURL) {
                    Label("Write the email to \(normalizedEmail)", systemImage: "envelope")
                }
            }

            ShareLink(item: InviteMessage.text(
                code: code,
                role: kind == .subject ? .subject : .caregiver,
                personName: selectedPersonName
            )) {
                Label(
                    normalizedEmail.isEmpty ? "Share the invitation" : "Share another way",
                    systemImage: "square.and.arrow.up"
                )
            }
        } header: {
            Text("Invitation ready")
        } footer: {
            // Read aloud over the phone is the realistic delivery mechanism, so
            // the alphabet already excludes characters that sound alike.
            Text(normalizedEmail.isEmpty
                 ? "Good for 48 hours, and works once. You can read it out over the phone."
                 : "Nothing has been sent yet. Good for 48 hours, and works once.")
        }
    }

    private func generate() async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            code = try await groups.generateInviteCode(
                role: kind == .subject ? .subject : .caregiver,
                recipientID: kind == .subject ? recipientID : nil,
                email: normalizedEmail.isEmpty ? nil : normalizedEmail
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

