import SwiftUI

struct EditProfileView: View {
    @State private var editedProfile: Profile
    let onSave: (Profile) -> Void
    @Environment(\.dismiss) var dismiss

    init(profile: Profile, onSave: @escaping (Profile) -> Void) {
        _editedProfile = State(initialValue: profile)
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Text("Email")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(editedProfile.email)
                    }
                }

                Section("Personal Information") {
                    HStack {
                        Text("Name")
                        Spacer()
                        TextField("Name", text: $editedProfile.name)
                        .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Age")
                        Spacer()
                        Stepper("\(editedProfile.age)", value: $editedProfile.age, in: 1...120)
                    }

                    Picker("Gender", selection: $editedProfile.gender) {
                        ForEach(Gender.allCases, id: \.self) { gender in
                            Text(gender.displayName).tag(gender)
                        }
                    }
                }

                Section("Skin Profile") {
                    Picker("Skin Type", selection: $editedProfile.skinType) {
                        ForEach(1...6, id: \.self) { type in
                            HStack {
                                Text("Type \(type)")
                                if let skinType = FitzpatrickSkinType(rawValue: type) {
                                    Text("- \(skinType.description)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .tag(type)
                        }
                    }
                    .onChange(of: editedProfile.skinType) { newValue in
                        editedProfile.med = UVCalculations.calculateMED(
                            skinType: newValue,
                            age: editedProfile.age,
                            gender: editedProfile.gender
                        )
                    }

                    HStack {
                        Text("MED Value")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(editedProfile.med) J/m²")
                            .fontWeight(.semibold)
                    }

                    Text("Your MED (Minimal Erythemal Dose) is automatically calculated based on your skin type, age, and gender.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(editedProfile)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}