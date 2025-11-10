import SwiftUI
import CoreLocation
import AVFoundation
import CoreMotion

struct PermissionsView: View {
    let onComplete: () -> Void

    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var notificationManager: NotificationManager

    @State private var locationGranted = false
    @State private var locationAlwaysGranted = false
    @State private var notificationsGranted = false
    @State private var cameraGranted = false
    @State private var motionGranted = false
    @State private var showingCameraPermission = false

    var allPermissionsGranted: Bool {
        locationAlwaysGranted && notificationsGranted && cameraGranted && motionGranted
    }

    var body: some View {
        VStack(spacing: 30) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)

                Text("Permissions")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("We need a few permissions to provide the best experience")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)
            .padding(.horizontal, 20)

            // Permission cards
            VStack(spacing: 16) {
                PermissionCard(
                    title: "Location (Always)",
                    description: "Track UV exposure in the background",
                    icon: "location.fill",
                    isGranted: locationAlwaysGranted,
                    action: requestLocationPermission
                )

                PermissionCard(
                    title: "Motion & Fitness",
                    description: "Detect indoor, outdoor, and vehicle movement",
                    icon: "figure.walk",
                    isGranted: motionGranted,
                    action: requestMotionPermission
                )

                PermissionCard(
                    title: "Notifications",
                    description: "Alert you about UV exposure and reminders",
                    icon: "bell.fill",
                    isGranted: notificationsGranted,
                    action: requestNotificationPermission
                )

                PermissionCard(
                    title: "Camera",
                    description: "Capture photos for body scans",
                    icon: "camera.fill",
                    isGranted: cameraGranted,
                    action: requestCameraPermission
                )
            }
            .padding(.horizontal, 20)

            Spacer()

            // Continue button
            Button(action: onComplete) {
                HStack {
                    Text(allPermissionsGranted ? "Complete Setup" : "Grant Permissions First")
                    if allPermissionsGranted {
                        Image(systemName: "checkmark.circle.fill")
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(allPermissionsGranted ? Color.green : Color.gray)
                .cornerRadius(12)
                .animation(.easeInOut, value: allPermissionsGranted)
            }
            .disabled(!allPermissionsGranted)
            .padding(.horizontal, 20)

            // Skip option
            Button(action: onComplete) {
                Text("Skip for now")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 40)
        }
        .onAppear {
            checkPermissions()
        }
    }

    private func checkPermissions() {
        // Check location
        let locationStatus = CLLocationManager.authorizationStatus()
        locationGranted = (locationStatus == .authorizedAlways || locationStatus == .authorizedWhenInUse)
        locationAlwaysGranted = (locationStatus == .authorizedAlways)

        // Check notifications
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsGranted = settings.authorizationStatus == .authorized
            }
        }

        // Check camera (using AVFoundation)
        checkCameraPermission()
        
        // Check motion
        checkMotionPermission()
    }

    private func requestLocationPermission() {
        print("📍 [PermissionsView] Requesting ALWAYS location permission...")
        
        let currentStatus = CLLocationManager.authorizationStatus()
        
        if currentStatus == .notDetermined {
            // First time - request "When In Use" first (iOS requirement)
            locationManager.requestLocationPermission()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                // Then upgrade to "Always"
                print("📍 [PermissionsView] Upgrading to ALWAYS authorization...")
                locationManager.locationManagerInstance.requestAlwaysAuthorization()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    checkPermissions()
                    if locationAlwaysGranted {
                        print("✅ [PermissionsView] ALWAYS location permission granted")
                        locationManager.requestOneTimeLocation()
                    }
                }
            }
        } else if currentStatus == .authorizedWhenInUse {
            // Already have "When In Use" - upgrade to "Always"
            print("📍 [PermissionsView] Upgrading from 'When In Use' to ALWAYS...")
            locationManager.locationManagerInstance.requestAlwaysAuthorization()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                checkPermissions()
            }
        } else {
            // Permission denied or restricted - show alert to go to settings
            print("⚠️ [PermissionsView] Location permission denied - user must enable in Settings")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                checkPermissions()
            }
        }
    }
    
    private func requestMotionPermission() {
        print("🏃 [PermissionsView] Requesting motion & fitness permission...")
        
        let motionManager = CMMotionActivityManager()
        motionManager.queryActivityStarting(from: Date(), to: Date(), to: .main) { activities, error in
            DispatchQueue.main.async {
                if error == nil {
                    print("✅ [PermissionsView] Motion permission granted")
                    motionGranted = true
                } else {
                    print("⚠️ [PermissionsView] Motion permission denied: \(error?.localizedDescription ?? "unknown")")
                    motionGranted = false
                }
                checkPermissions()
            }
        }
    }
    
    private func checkMotionPermission() {
        // Motion permission is determined on first use
        // If user previously granted, they won't see dialog again
        // We'll assume granted for now and verify on first use
        if #available(iOS 11.0, *) {
            let status = CMMotionActivityManager.authorizationStatus()
            motionGranted = (status == .authorized)
        } else {
            motionGranted = CMMotionActivityManager.isActivityAvailable()
        }
    }

    private func requestNotificationPermission() {
        Task {
            let granted = await notificationManager.requestNotificationPermission()
            await MainActor.run {
                notificationsGranted = granted
            }
        }
    }

    private func requestCameraPermission() {
        print("📷 [PermissionsView] Requesting camera permission...")
        
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                self.cameraGranted = granted
                if granted {
                    print("✅ [PermissionsView] Camera permission granted")
                } else {
                    print("⚠️ [PermissionsView] Camera permission denied")
                }
            }
        }
    }

    private func checkCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        cameraGranted = (status == .authorized)
    }
}

struct PermissionCard: View {
    let title: String
    let description: String
    let icon: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(isGranted ? .green : .orange)
                .frame(width: 40, height: 40)
                .background((isGranted ? Color.green : Color.orange).opacity(0.1))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
            } else {
                Button(action: action) {
                    Text("Allow")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.orange)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        )
    }
}