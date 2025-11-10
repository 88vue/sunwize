import SwiftUI

#if canImport(PhotosUI)
import PhotosUI
#endif

struct InlineSpotFormView: View {
    let coordinates: SIMD3<Float>
    let existingLocation: BodyLocation?
    let onSave: (SpotFormData) -> Void
    let onCancel: () -> Void
    
    @State private var formData: SpotFormData
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    
    #if canImport(PhotosUI)
    @State private var selectedPhotoItem: PhotosPickerItem?
    #endif
    
    init(coordinates: SIMD3<Float>, existingLocation: BodyLocation?, onSave: @escaping (SpotFormData) -> Void, onCancel: @escaping () -> Void) {
        self.coordinates = coordinates
        self.existingLocation = existingLocation
        self.onSave = onSave
        self.onCancel = onCancel
        
        let bodyPart = existingLocation?.bodyPart ?? BodyPart.from(coordinates: coordinates).rawValue
        _formData = State(initialValue: SpotFormData(
            coordinates: coordinates,
            location: existingLocation,
            bodyPart: bodyPart
        ))
    }


    
    var body: some View {
        VStack(spacing: 0) {
            // Custom header with Cancel and Save buttons
            HStack {
                Button(action: onCancel) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.body)
                        Text("Cancel")
                    }
                    .foregroundColor(.orange)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                }
                
                Spacer()
                
                Text(existingLocation == nil ? "New Spot" : "Add Log")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    onSave(formData)
                }) {
                    Text("Save")
                        .fontWeight(.semibold)
                        .foregroundColor(formData.image == nil ? .gray : .orange)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                }
                .disabled(formData.image == nil)
            }
            .background(Color(.systemBackground))
            .overlay(
                Divider(),
                alignment: .bottom
            )
            
            ScrollView {
                VStack(spacing: 20) {
                    // Camera section
                    VStack(spacing: 12) {
                        if let image = formData.image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 300)
                                .cornerRadius(12)
                                .overlay(
                                    Button(action: { formData.image = nil }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.white)
                                            .background(Color.black.opacity(0.5))
                                            .clipShape(Circle())
                                    }
                                    .padding(8),
                                    alignment: .topTrailing
                                )
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 60))
                                    .foregroundColor(.gray)
                                
                                Text("Take a photo of the spot")
                                    .font(.headline)
                                
                                HStack(spacing: 20) {
                                    Button(action: { showingCamera = true }) {
                                        Label("Camera", systemImage: "camera.fill")
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                            .padding()
                                            .background(Color.orange)
                                            .cornerRadius(12)
                                    }
                                    
                                    #if canImport(PhotosUI)
                                    if #available(iOS 16.0, *) {
                                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                            Label("Library", systemImage: "photo.on.rectangle")
                                                .font(.subheadline)
                                                .foregroundColor(.white)
                                                .padding()
                                                .background(Color.blue)
                                                .cornerRadius(12)
                                        }
                                    } else {
                                        Button(action: { showingPhotoPicker = true }) {
                                            Label("Library", systemImage: "photo.on.rectangle")
                                                .font(.subheadline)
                                                .foregroundColor(.white)
                                                .padding()
                                                .background(Color.blue)
                                                .cornerRadius(12)
                                        }
                                    }
                                    #else
                                    Button(action: { showingPhotoPicker = true }) {
                                        Label("Library", systemImage: "photo.on.rectangle")
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                            .padding()
                                            .background(Color.blue)
                                            .cornerRadius(12)
                                    }
                                    #endif
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Body part
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Body Part", systemImage: "figure.stand")
                            .font(.headline)
                        
                        Text(formData.bodyPart)
                            .font(.subheadline)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    // ABCDE Assessment
                    VStack(alignment: .leading, spacing: 16) {
                        Label("ABCDE Assessment", systemImage: "checklist")
                            .font(.headline)
                        
                        // Asymmetry
                        Toggle(isOn: $formData.asymmetry) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Asymmetry")
                                    .font(.subheadline)
                                Text("One half unlike the other")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tint(.orange)
                        
                        // Border
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Border")
                                .font(.subheadline)
                            Picker("Border", selection: $formData.border) {
                                Text("Regular").tag(BorderType.regular)
                                Text("Irregular").tag(BorderType.irregular)
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        // Color
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Color")
                                .font(.subheadline)
                            Picker("Color", selection: $formData.color) {
                                Text("Uniform").tag(ColorType.uniform)
                                Text("Varied").tag(ColorType.varied)
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        // Diameter
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Diameter")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(Int(formData.diameter)) mm")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(formData.diameter > 6 ? .red : .primary)
                            }
                            Slider(value: $formData.diameter, in: 0...10, step: 1)
                                .tint(formData.diameter > 6 ? .red : .orange)
                        }
                        
                        // Evolving
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Evolution")
                                .font(.subheadline)
                            Picker("Evolution", selection: $formData.evolving) {
                                Text("Shrunk").tag(EvolvingType.shrunk)
                                Text("Unchanged").tag(EvolvingType.unchanged)
                                Text("Grown").tag(EvolvingType.grown)
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        // Warning if concerning features
                        if formData.diameter > 6 || formData.evolving == .grown {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text("Consider consulting a dermatologist")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Description", systemImage: "text.alignleft")
                            .font(.headline)
                        
                        TextField("Describe the spot", text: $formData.description)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.horizontal)
                    
                    // Notes
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Notes (Optional)", systemImage: "note.text")
                            .font(.headline)
                        
                        TextEditor(text: $formData.notes)
                            .frame(height: 100)
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraView(image: $formData.image)
        }
        #if canImport(PhotosUI)
        .onChange(of: selectedPhotoItem) { newItem in
            if #available(iOS 16.0, *) {
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        formData.image = image
                    }
                }
            }
        }
        #endif
    }
}
