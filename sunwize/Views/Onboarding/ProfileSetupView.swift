import SwiftUI

struct ProfileSetupView: View {
    @Binding var profileData: ProfileData
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "person.text.rectangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)

                    Text("Your Profile")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Help us personalize your experience")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)

                // Form fields
                VStack(spacing: 20) {
                    // Name
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Name", systemImage: "person.fill")
                            .font(.headline)
                            .foregroundColor(.primary)

                        TextField("Enter your name", text: $profileData.name)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                    }

                    // Age
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Age", systemImage: "calendar")
                            .font(.headline)
                            .foregroundColor(.primary)

                        HStack {
                            Slider(value: Binding(
                                get: { Double(profileData.age) },
                                set: { profileData.age = Int($0) }
                            ), in: 1...120, step: 1)

                            Text("\(profileData.age)")
                                .font(.headline)
                                .foregroundColor(.orange)
                                .frame(width: 50)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }

                    // Gender
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Gender", systemImage: "person.2.fill")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Picker("Gender", selection: $profileData.gender) {
                            ForEach(Gender.allCases, id: \.self) { gender in
                                Text(gender.displayName).tag(gender)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Skin Type
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Skin Type", systemImage: "sun.max.fill")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("Select your Fitzpatrick skin type")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        SkinTypePicker(selectedType: $profileData.skinType)
                    }
                }
                .padding(.horizontal, 20)

                // Navigation buttons
                HStack(spacing: 16) {
                    Button(action: onBack) {
                        Image(systemName: "arrow.left")
                            .font(.headline)
                            .foregroundColor(.orange)
                            .frame(width: 50, height: 50)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(12)
                    }

                    Button(action: {
                        guard !profileData.name.isEmpty else { return }
                        onContinue()
                    }) {
                        HStack {
                            Text("Continue")
                            Image(systemName: "arrow.right")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .cornerRadius(12)
                    }
                    .disabled(profileData.name.isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Skin Type Picker
struct SkinTypePicker: View {
    @Binding var selectedType: Int
    @State private var showingDetails = false

    let skinTypes: [(type: FitzpatrickSkinType, color: Color)] = [
        (.typeI, Color(red: 1.0, green: 0.95, blue: 0.9)),
        (.typeII, Color(red: 1.0, green: 0.9, blue: 0.8)),
        (.typeIII, Color(red: 0.95, green: 0.85, blue: 0.7)),
        (.typeIV, Color(red: 0.9, green: 0.75, blue: 0.6)),
        (.typeV, Color(red: 0.7, green: 0.55, blue: 0.4)),
        (.typeVI, Color(red: 0.5, green: 0.35, blue: 0.25))
    ]

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(skinTypes, id: \.type) { item in
                        SkinTypeCard(
                            skinType: item.type,
                            color: item.color,
                            isSelected: selectedType == item.type.rawValue,
                            onTap: {
                                selectedType = item.type.rawValue
                            }
                        )
                    }
                }
            }

            // Selected type description
            if let selected = FitzpatrickSkinType(rawValue: selectedType) {
                Text(selected.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
            }

            Button(action: { showingDetails = true }) {
                Text("Learn more about skin types")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .sheet(isPresented: $showingDetails) {
            SkinTypeDetailsView(selectedType: $selectedType)
        }
    }
}

struct SkinTypeCard: View {
    let skinType: FitzpatrickSkinType
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 60, height: 60)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.orange : Color.gray.opacity(0.3), lineWidth: 3)
                )

            Text("Type \(skinType.rawValue)")
                .font(.caption)
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundColor(isSelected ? .orange : .secondary)
        }
        .onTapGesture {
            onTap()
        }
    }
}

struct SkinTypeDetailsView: View {
    @Binding var selectedType: Int
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("The Fitzpatrick scale is a numerical classification for human skin color. It was developed in 1975 by Harvard Medical School dermatologist Thomas Fitzpatrick as a way to classify the typical response of different types of skin to ultraviolet light.")
                        .font(.body)
                        .padding()

                    ForEach(FitzpatrickSkinType.allCases, id: \.self) { type in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Type \(type.rawValue)")
                                .font(.headline)
                                .foregroundColor(.orange)

                            Text(type.description)
                                .font(.body)

                            HStack {
                                Label("Base MED", systemImage: "sun.max")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(type.baseMED) J/m²")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)

                            if selectedType == type.rawValue {
                                Label("Selected", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemBackground))
                                .shadow(radius: 2)
                        )
                        .onTapGesture {
                            selectedType = type.rawValue
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Skin Types")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}