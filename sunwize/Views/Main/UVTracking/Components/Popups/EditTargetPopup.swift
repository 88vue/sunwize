import SwiftUI

/// Bottom sheet popup for editing daily vitamin D target
struct EditTargetPopup: View {
    // MARK: - Properties
    @Binding var isPresented: Bool
    @Binding var targetIU: Double
    let onSave: (Double) -> Void

    @State private var tempTarget: Double
    @FocusState private var isInputFocused: Bool

    // MARK: - Initialization
    init(isPresented: Binding<Bool>, targetIU: Binding<Double>, onSave: @escaping (Double) -> Void) {
        self._isPresented = isPresented
        self._targetIU = targetIU
        self.onSave = onSave
        self._tempTarget = State(initialValue: targetIU.wrappedValue)
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // Header
            BottomSheetHeader(title: "Edit Daily Target", isPresented: $isPresented)

            VStack(spacing: 24) {
                // Target input field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Target IU per day")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.slate700)

                    TextField("", text: Binding(
                        get: { formatTargetInput(tempTarget) },
                        set: { newValue in
                            if let value = Double(newValue.replacingOccurrences(of: ",", with: "")) {
                                tempTarget = value
                            }
                        }
                    ))
                    .keyboardType(.numberPad)
                    .focused($isInputFocused)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.black)
                    .frame(height: 66)
                    .background(Color.white)
                    .cornerRadius(CornerRadius.base)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.base)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                }

                // Info box
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recommended Range")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.black)

                        Text("Most adults need 1,000-2,000 IU daily. Consult your healthcare provider for personalized recommendations.")
                            .font(.system(size: 12))
                            .foregroundColor(.slate700)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(17)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.vitaminDInfoBlue)
                .cornerRadius(CornerRadius.base)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.base)
                        .stroke(Color.vitaminDInfoBorder, lineWidth: 1)
                )

                // Quick select buttons
                VStack(spacing: 16) {
                    QuickSelectButton(
                        value: 1000,
                        label: "Minimum",
                        isSelected: tempTarget == 1000
                    ) {
                        tempTarget = 1000
                        isInputFocused = false
                    }

                    QuickSelectButton(
                        value: 2000,
                        label: "Standard",
                        isSelected: tempTarget == 2000
                    ) {
                        tempTarget = 2000
                        isInputFocused = false
                    }

                    QuickSelectButton(
                        value: 4000,
                        label: "Maximum safe",
                        isSelected: tempTarget == 4000
                    ) {
                        tempTarget = 4000
                        isInputFocused = false
                    }
                }

                // Save button
                Button(action: {
                    targetIU = tempTarget
                    onSave(tempTarget)
                    withAnimation {
                        isPresented = false
                    }
                }) {
                    Text("Save Target")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.buttonHeight)
                        .background(Color.vitaminDOrange)
                        .cornerRadius(CornerRadius.base)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 8)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, 110)
        }
        .background(Color(.systemBackground))
        .cornerRadius(CornerRadius.lg, corners: [.topLeft, .topRight])
        .shadow(.medium)
        .dragToDismiss($isPresented)
    }

    // MARK: - Helpers
    private func formatTargetInput(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ""
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }
}

// MARK: - Quick Select Button
struct QuickSelectButton: View {
    let value: Int
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text("\(value.formattedAsIU()) IU")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)

                Spacer()

                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.slate600)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Color(.systemGray6))
            .cornerRadius(CornerRadius.base)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview
#Preview("Edit Target Popup") {
    struct PreviewWrapper: View {
        @State private var isPresented = true
        @State private var targetIU: Double = 2000

        var body: some View {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack {
                    Text("Target: \(Int(targetIU)) IU")
                        .font(.largeTitle)

                    Button("Show Popup") {
                        isPresented = true
                    }
                }

                if isPresented {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            isPresented = false
                        }

                    VStack {
                        Spacer()
                        EditTargetPopup(
                            isPresented: $isPresented,
                            targetIU: $targetIU,
                            onSave: { newValue in
                                print("Saved target: \(newValue)")
                            }
                        )
                    }
                    .transition(.move(edge: .bottom))
                }
            }
        }
    }

    return PreviewWrapper()
}
