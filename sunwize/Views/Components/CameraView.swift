import SwiftUI
import AVFoundation

struct CameraView: View {
    @Binding var image: UIImage?
    @Environment(\.dismiss) var dismiss
    @StateObject private var camera = CameraModel()
    
    var body: some View {
        ZStack {
            // Camera preview
            CameraPreview(camera: camera)
                .ignoresSafeArea()
            
            // Camera controls overlay
            VStack {
                // Top bar with close button
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding()
                
                Spacer()
                
                // Bottom controls
                HStack {
                    Spacer()
                    
                    // Capture button
                    Button(action: {
                        camera.capturePhoto()
                    }) {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 3)
                                .frame(width: 70, height: 70)
                            
                            Circle()
                                .fill(Color.white)
                                .frame(width: 60, height: 60)
                        }
                    }
                    .disabled(!camera.isSessionRunning)
                    
                    Spacer()
                }
                .padding(.bottom, 40)
            }
            
            // Loading indicator
            if camera.isCapturing {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            }
        }
        .onAppear {
            camera.checkPermissions()
        }
        .onChange(of: camera.capturedImage) { newImage in
            if let newImage = newImage {
                image = newImage
                dismiss()
            }
        }
        .alert("Camera Permission Required", isPresented: $camera.showPermissionAlert) {
            Button("Cancel", role: .cancel) {
                dismiss()
            }
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                dismiss()
            }
        } message: {
            Text("Please allow camera access in Settings to take photos of spots.")
        }
        .alert("Camera Error", isPresented: $camera.showErrorAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text(camera.errorMessage)
        }
    }
}

// MARK: - Camera Preview
struct CameraPreview: UIViewRepresentable {
    @ObservedObject var camera: CameraModel
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        
        camera.preview = AVCaptureVideoPreviewLayer(session: camera.session)
        camera.preview.videoGravity = .resizeAspectFill
        camera.preview.frame = view.bounds
        
        view.layer.addSublayer(camera.preview)
        
        DispatchQueue.global(qos: .userInitiated).async {
            camera.session.startRunning()
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            camera.preview.frame = uiView.bounds
        }
    }
}

// MARK: - Camera Model
class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    @Published var capturedImage: UIImage?
    @Published var isCapturing = false
    @Published var showPermissionAlert = false
    @Published var showErrorAlert = false
    @Published var isSessionRunning = false
    @Published var errorMessage = ""
    
    let session = AVCaptureSession()
    var preview = AVCaptureVideoPreviewLayer()
    private var photoOutput = AVCapturePhotoOutput()
    private var currentDevice: AVCaptureDevice?
    
    override init() {
        super.init()
    }
    
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCamera()
                    } else {
                        self?.showPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.showPermissionAlert = true
            }
        @unknown default:
            break
        }
    }
    
    private func setupCamera() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                self.session.beginConfiguration()
                
                // Set session preset
                self.session.sessionPreset = .photo
                
                // Get camera device
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    throw CameraError.deviceNotFound
                }
                self.currentDevice = device
                
                // Create input
                let input = try AVCaptureDeviceInput(device: device)
                
                // Add input
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                } else {
                    throw CameraError.cannotAddInput
                }
                
                // Add output
                if self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                    
                    // Configure photo output
                    self.photoOutput.isHighResolutionCaptureEnabled = true
                    if let connection = self.photoOutput.connection(with: .video) {
                        connection.videoOrientation = .portrait
                    }
                } else {
                    throw CameraError.cannotAddOutput
                }
                
                self.session.commitConfiguration()
                
                DispatchQueue.main.async {
                    self.isSessionRunning = true
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.showErrorAlert = true
                    print("❌ Camera setup error: \(error)")
                }
            }
        }
    }
    
    func capturePhoto() {
        guard !isCapturing else { return }
        
        isCapturing = true
        
        let settings = AVCapturePhotoSettings()
        
        // Enable high resolution
        settings.isHighResolutionPhotoEnabled = true
        
        // Set flash mode to auto
        if let device = currentDevice, device.hasFlash {
            settings.flashMode = .auto
        }
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    // MARK: - AVCapturePhotoCaptureDelegate
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        isCapturing = false
        
        if let error = error {
            print("❌ Photo capture error: \(error)")
            errorMessage = "Failed to capture photo"
            showErrorAlert = true
            return
        }
        
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            print("❌ Could not convert photo to image")
            errorMessage = "Failed to process photo"
            showErrorAlert = true
            return
        }
        
        // Fix orientation if needed
        let fixedImage = image.fixOrientation()
        
        DispatchQueue.main.async {
            self.capturedImage = fixedImage
        }
    }
    
    deinit {
        if session.isRunning {
            session.stopRunning()
        }
    }
}

// MARK: - Camera Errors
enum CameraError: LocalizedError {
    case deviceNotFound
    case cannotAddInput
    case cannotAddOutput
    
    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "Camera device not found"
        case .cannotAddInput:
            return "Cannot add camera input"
        case .cannotAddOutput:
            return "Cannot add photo output"
        }
    }
}

// MARK: - UIImage Extension for Orientation Fix
extension UIImage {
    func fixOrientation() -> UIImage {
        if imageOrientation == .up {
            return self
        }
        
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return normalizedImage ?? self
    }
}
