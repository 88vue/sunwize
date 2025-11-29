import SwiftUI

/// Reusable form text field with label and styled input
/// Used in EditProfilePopup and other forms throughout the app
struct FormTextField: View {
    // MARK: - Properties
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboardType: UIKeyboardType = .default

    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(label)
                .font(.system(size: Typography.subheadline, weight: .medium))
                .foregroundColor(.slate700)

            TextField(placeholder, text: $text)
                .font(.system(size: Typography.body))
                .foregroundColor(.textPrimary)
                .keyboardType(keyboardType)
                .padding(.horizontal, Spacing.base)
                .frame(height: 52)
                .background(Color(.systemGray6))
                .cornerRadius(CornerRadius.sm)
        }
    }
}

/// Number field variant with Int binding
/// Includes a "Done" toolbar button for numberPad keyboard dismissal
struct FormNumberField: View {
    // MARK: - Properties
    let label: String
    @Binding var value: Int
    var placeholder: String = ""
    var suffix: String? = nil

    @FocusState private var isFocused: Bool

    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(label)
                .font(.system(size: Typography.subheadline, weight: .medium))
                .foregroundColor(.slate700)

            HStack(spacing: Spacing.sm) {
                TextField(placeholder, text: Binding(
                    get: { value > 0 ? String(value) : "" },
                    set: { newValue in
                        if let intValue = Int(newValue) {
                            value = intValue
                        } else if newValue.isEmpty {
                            value = 0
                        }
                    }
                ))
                .font(.system(size: Typography.body))
                .foregroundColor(.textPrimary)
                .keyboardType(.numberPad)
                .focused($isFocused)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            isFocused = false
                        }
                        .fontWeight(.semibold)
                    }
                }

                if let suffix = suffix {
                    Text(suffix)
                        .font(.system(size: Typography.body))
                        .foregroundColor(.slate500)
                }
            }
            .padding(.horizontal, Spacing.base)
            .frame(height: 52)
            .background(Color(.systemGray6))
            .cornerRadius(CornerRadius.sm)
        }
    }
}

// MARK: - Preview
#Preview("Form Text Field") {
    VStack(spacing: Spacing.lg) {
        FormTextField(
            label: "Name",
            text: .constant("John Doe"),
            placeholder: "Enter your name"
        )

        FormNumberField(
            label: "Age",
            value: .constant(30),
            placeholder: "Enter age",
            suffix: "years"
        )

        FormTextField(
            label: "Email",
            text: .constant("john@example.com"),
            placeholder: "Enter email",
            keyboardType: .emailAddress
        )
    }
    .padding()
    .background(Color(.systemBackground))
}
