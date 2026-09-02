import SwiftUI

/// The keypad that swaps the phone back to the caregiver's app, and the sheet
/// that sets the code in the first place.
///
/// Deliberately not `SecureField`: the person keying this in is often standing
/// up, holding a bag, and reading without glasses. Big fixed buttons and four
/// visible dots beat a text field and a system keyboard here.

// MARK: - Entry

struct CaregiverPINEntryView: View {
    /// What the code is being used for, so the sheet can say it.
    enum Purpose {
        case unlock
        case confirmChange

        var title: String {
            switch self {
            case .unlock: return "Caregiver code"
            case .confirmChange: return "Enter your code"
            }
        }

        var detail: String {
            switch self {
            case .unlock: return "Enter the code to go back to the full app."
            case .confirmChange: return "Enter the current code to change it."
            }
        }
    }

    let purpose: Purpose
    /// Returns true when the code was accepted, which dismisses the sheet.
    let onSubmit: (String) -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var digits = ""
    @State private var isWrong = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.tint)
                    Text(purpose.detail)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)

                dots

                if isWrong {
                    Text("That code did not match.")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                } else {
                    // Reserved either way, so the keypad never jumps under a
                    // thumb that is already moving.
                    Text(" ")
                        .font(.subheadline)
                }

                keypad

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .navigationTitle(purpose.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 20) {
            ForEach(0..<DeviceModeService.pinLength, id: \.self) { index in
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1.5)
                    .background(
                        Circle().fill(index < digits.count ? Color.accentColor : .clear)
                    )
                    .frame(width: 18, height: 18)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(digits.count) of \(DeviceModeService.pinLength) digits entered")
    }

    private var keypad: some View {
        VStack(spacing: 14) {
            ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "<"]], id: \.self) { row in
                HStack(spacing: 14) {
                    ForEach(row, id: \.self) { key in
                        keyButton(key)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func keyButton(_ key: String) -> some View {
        if key.isEmpty {
            Color.clear.frame(width: 74, height: 62)
        } else {
            Button {
                press(key)
            } label: {
                Group {
                    if key == "<" {
                        Image(systemName: "delete.left")
                            .font(.title2)
                    } else {
                        Text(key)
                            .font(.system(size: 28, weight: .medium, design: .rounded))
                    }
                }
                .frame(width: 74, height: 62)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(key == "<" ? "Delete" : key)
        }
    }

    private func press(_ key: String) {
        isWrong = false
        if key == "<" {
            if !digits.isEmpty { digits.removeLast() }
            return
        }
        guard digits.count < DeviceModeService.pinLength else { return }
        digits.append(key)
        guard digits.count == DeviceModeService.pinLength else { return }

        if onSubmit(digits) {
            dismiss()
        } else {
            isWrong = true
            digits = ""
        }
    }
}

// MARK: - Setting the code

struct SetCaregiverPINSheet: View {
    @Environment(DeviceModeService.self) private var deviceMode
    @Environment(\.dismiss) private var dismiss

    @State private var first = ""
    @State private var second = ""
    @State private var error: String?
    @State private var isConfirmingRemoval = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("4-digit code", text: $first)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                    TextField("Enter it again", text: $second)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                } header: {
                    Text("Caregiver code")
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text("Asked for when this phone comes back from the person you're caring for. It never covers the emergency card.")
                    }
                }

                if deviceMode.hasPIN {
                    Section {
                        // Asked, like every other action in the app that
                        // gives something up. The footer said what the
                        // consequence was and the button did it on one tap
                        // anyway, and this is the single control deciding
                        // whether a phone that has been handed over stays on
                        // the check-in screen or opens straight back into the
                        // whole record.
                        Button("Remove the code", role: .destructive) {
                            isConfirmingRemoval = true
                        }
                    } footer: {
                        Text("Without a code, anyone holding the phone can switch back to the full app.")
                    }
                }
            }
            .navigationTitle(deviceMode.hasPIN ? "Change Code" : "Set a Code")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Remove the caregiver code?",
                isPresented: $isConfirmingRemoval,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    deviceMode.clearPIN()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Anyone holding this phone will be able to switch out of the check-in screen and into the full care record.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(first.isEmpty || second.isEmpty)
                }
            }
        }
    }

    private func save() {
        guard DeviceModeService.isWellFormed(first) else {
            error = "The code has to be \(DeviceModeService.pinLength) digits."
            return
        }
        guard first == second else {
            error = "The two codes are not the same."
            return
        }
        deviceMode.setPIN(first)
        dismiss()
    }
}

#Preview("Entry") {
    CaregiverPINEntryView(purpose: .unlock) { _ in false }
}
