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
    @State private var dragOffset: CGFloat = 0
    @State private var keyboardHeight: CGFloat = 0
    
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
            // Header
            VStack(spacing: 0) {
                // Drag handle
                RoundedRectangle(cornerRadius: 9999)
                    .fill(Color(.systemGray3))
                    .frame(width: Layout.dragHandleWidth, height: Layout.dragHandleHeight)
                    .padding(.top, Spacing.BottomSheet.dragHandleTop)
                    .padding(.bottom, Spacing.BottomSheet.dragHandleBottom)
                
                HStack(alignment: .top) {
                    Text("Add New Spot")
                        .font(.system(size: Typography.title3, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: Typography.footnote, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: Layout.iconButtonSize, height: Layout.iconButtonSize)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.BottomSheet.headerBottom)
            }
            .background(Color(.systemBackground)) // Ensure it captures touches
            
            // Scrollable content
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Photo Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Photo")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        if let image = formData.image {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 176)
                                    .clipped()
                                    .cornerRadius(16)
                                
                                Button(action: { formData.image = nil }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                        .background(Color.black.opacity(0.5))
                                        .clipShape(Circle())
                                }
                                .padding(8)
                            }
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.gray)
                                    .padding(.top, 28)
                                
                                Text("Take or upload a photo")
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                                
                                HStack(spacing: 12) {
                                    Button(action: { showingCamera = true }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 14))
                                            Text("Camera")
                                                .font(.system(size: 14))
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .frame(height: 36)
                                        .background(Color.orange)
                                        .cornerRadius(12)
                                    }
                                    
                                    #if canImport(PhotosUI)
                                    if #available(iOS 16.0, *) {
                                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                            HStack(spacing: 8) {
                                                Image(systemName: "photo.fill")
                                                    .font(.system(size: 14))
                                                Text("Gallery")
                                                    .font(.system(size: 14))
                                            }
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 16)
                                            .frame(height: 36)
                                            .background(Color(.systemGray5))
                                            .cornerRadius(12)
                                        }
                                    } else {
                                        Button(action: { showingPhotoPicker = true }) {
                                            HStack(spacing: 8) {
                                                Image(systemName: "photo.fill")
                                                    .font(.system(size: 14))
                                                Text("Gallery")
                                                    .font(.system(size: 14))
                                            }
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 16)
                                            .frame(height: 36)
                                            .background(Color(.systemGray5))
                                            .cornerRadius(12)
                                        }
                                    }
                                    #else
                                    Button(action: { showingPhotoPicker = true }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "photo.fill")
                                                .font(.system(size: 14))
                                            Text("Gallery")
                                                .font(.system(size: 14))
                                        }
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 16)
                                        .frame(height: 36)
                                        .background(Color(.systemGray5))
                                        .cornerRadius(12)
                                    }
                                    #endif
                                }
                                .padding(.bottom, 16)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 176)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color(.systemGray4), style: StrokeStyle(lineWidth: 2, dash: [5]))
                            )
                        }
                    }
                    
                    // Asymmetry Toggle
                    VStack(spacing: 8) {
                        HStack {
                            Text("Asymmetry")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Toggle("", isOn: $formData.asymmetry)
                                .labelsHidden()
                                .tint(.orange)
                        }
                        
                        Text("Is one half different from the other?")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    
                    // Border Selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Border")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            ForEach(BorderType.allCases, id: \.self) { borderType in
                                Button(action: { formData.border = borderType }) {
                                    Text(borderType.rawValue)
                                        .font(.system(size: 14))
                                        .foregroundColor(formData.border == borderType ? .white : .secondary)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 36)
                                        .background(formData.border == borderType ? Color.orange : Color(.systemGray5))
                                        .cornerRadius(12)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    
                    // Color Selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Color")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            ForEach(ColorType.allCases, id: \.self) { colorType in
                                Button(action: { formData.color = colorType }) {
                                    Text(colorType.rawValue)
                                        .font(.system(size: 14))
                                        .foregroundColor(formData.color == colorType ? .white : .secondary)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 36)
                                        .background(formData.color == colorType ? Color.orange : Color(.systemGray5))
                                        .cornerRadius(12)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    
                    // Diameter Slider
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Diameter: \(Int(formData.diameter))mm")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        Slider(value: $formData.diameter, in: 1...20, step: 1)
                            .tint(.blue)
                        
                        HStack {
                            Text("1mm")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("20mm")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(16)
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    
                    // Evolving Status Selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Evolving Status")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            ForEach(EvolvingType.allCases, id: \.self) { evolvingType in
                                Button(action: { formData.evolving = evolvingType }) {
                                    Text(evolvingType.rawValue)
                                        .font(.system(size: 14))
                                        .foregroundColor(formData.evolving == evolvingType ? .white : .secondary)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 36)
                                        .background(formData.evolving == evolvingType ? Color.orange : Color(.systemGray5))
                                        .cornerRadius(12)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    
                    // Notes
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes (Optional)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        ZStack(alignment: .topLeading) {
                            if formData.notes.isEmpty {
                                Text("Add any additional observations...")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(.placeholderText))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 16)
                            }
                            
                            TextEditor(text: $formData.notes)
                                .font(.system(size: 16))
                                .frame(height: 106)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                                .toolbar {
                                    ToolbarItemGroup(placement: .keyboard) {
                                        Spacer()
                                        Button("Done") {
                                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                        }
                                    }
                                }
                        }
                        .background(Color(.systemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                        .cornerRadius(16)
                    }
                    
                    // Action Buttons
                    HStack(spacing: 12) {
                        Button(action: onCancel) {
                            Text("Cancel")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color(.systemGray5))
                                .cornerRadius(16)
                        }
                        
                        Button(action: {
                            onSave(formData)
                        }) {
                            Text("Save Spot")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(formData.image == nil ? Color.gray : Color.orange)
                                .cornerRadius(16)
                        }
                        .disabled(formData.image == nil)
                    }
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 24)
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(CornerRadius.lg, corners: [.topLeft, .topRight])
        .shadow(.medium)
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 100 {
                        onCancel()
                    } else {
                        withAnimation {
                            dragOffset = 0
                        }
                    }
                }
        )
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
        .padding(.bottom, keyboardHeight)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.easeOut(duration: 0.25)) {
                    self.keyboardHeight = keyboardFrame.height
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                self.keyboardHeight = 0
            }
        }
    }
}
