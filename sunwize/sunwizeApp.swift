//
//  sunwizeApp.swift
//  sunwize
//
//  Created by Anthony Greenall-Ota on 8/11/2025.
//

import SwiftUI
import BackgroundTasks
import CoreLocation

@main
struct sunwizeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authService)
                .environmentObject(locationManager)
                .environmentObject(notificationManager)
                .onAppear {
                    setupApp()
                }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
    }

    private func setupApp() {
        // Register background tasks
        BackgroundTaskManager.shared.registerBackgroundTasks()
        BackgroundTaskManager.shared.scheduleBackgroundTasks()

        // Setup notification categories
        notificationManager.setupNotificationCategories()

        // Check auth status (this will initialize location services if user is already signed in)
        authService.checkAuthStatus()
        
        print("🚀 [sunwizeApp] App initialized - background tasks registered")
        
        // NOTE: Location tracking initialization is now handled by AuthenticationService
        // after successful login/onboarding completion to ensure immediate GPS activation
    }
    
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            print("📱 [sunwizeApp] App became ACTIVE")
            // App in foreground - location updates continue automatically
            // LocationManager handles background updates natively via iOS
            
        case .inactive:
            print("📱 [sunwizeApp] App became INACTIVE (transitioning)")
            // Transitioning state - no action needed
            
        case .background:
            print("📱 [sunwizeApp] App entered BACKGROUND")
            // Background location tracking continues automatically
            // LocationManager uses iOS native background updates
            
            // Ensure background tasks are scheduled
            BackgroundTaskManager.shared.scheduleBackgroundTasks()
            
        @unknown default:
            break
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Configure app appearance
        configureAppearance()
        return true
    }

    private func configureAppearance() {
        // Set navigation bar appearance
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.systemOrange
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance

        // Set tab bar appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor.systemBackground

        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }
}
