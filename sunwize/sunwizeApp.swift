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
                .preferredColorScheme(.light)
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

        // Request notification permission if not already determined
        Task {
            await requestNotificationPermissionIfNeeded()

            // Schedule recurring notifications after permission is granted
            await scheduleRecurringNotifications()
        }

        // NOTE: Auth status check happens automatically in AuthenticationService.init()
        // which triggers location services initialization if user is already signed in

        print("🚀 [sunwizeApp] App initialized - background tasks registered")

        // NOTE: Location tracking initialization is now handled by AuthenticationService
        // after successful login/onboarding completion to ensure immediate GPS activation
    }

    private func scheduleRecurringNotifications() async {
        // Only schedule if notifications are authorized
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            print("⚠️ [sunwizeApp] Notifications not authorized - skipping recurring notification setup")
            return
        }

        // Schedule monthly body spot tracker reminder (1st of each month at 10 AM)
        await notificationManager.scheduleMonthlyBodySpotReminder()

        // Note: Morning UV peak notification is scheduled daily in BackgroundTaskManager's
        // daily maintenance task, as it requires fresh forecast data to show accurate peak times

        print("✅ [sunwizeApp] Recurring notifications scheduled")
    }

    private func requestNotificationPermissionIfNeeded() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()

        // Only auto-request if permission not determined
        if settings.authorizationStatus == .notDetermined {
            print("🔔 [sunwizeApp] Notification permission not determined - requesting...")
            let _ = await notificationManager.requestNotificationPermission()
        } else if settings.authorizationStatus == .authorized {
            print("✅ [sunwizeApp] Notifications already authorized")
        } else {
            print("⚠️ [sunwizeApp] Notifications denied - user must enable in Settings")
        }
    }
    
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            print("📱 [sunwizeApp] App became ACTIVE")
            // App in foreground - location updates continue automatically
            // LocationManager handles background updates natively via iOS

            // Check for day change (handles midnight reset if app was backgrounded overnight)
            Task {
                await BackgroundTaskManager.shared.checkForDayChange()
            }

        case .inactive:
            print("📱 [sunwizeApp] App became INACTIVE (transitioning)")
            // Transitioning state - no action needed

        case .background:
            print("📱 [sunwizeApp] App entered BACKGROUND")
            // Background location tracking continues automatically
            // LocationManager uses iOS native background updates

            // Sync Vitamin D data to database before backgrounding (safety measure)
            Task {
                await BackgroundTaskManager.shared.syncVitaminDToDatabase()
            }

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

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .portrait
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

    // MARK: - Push Notifications

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            NotificationManager.shared.registerDeviceToken(deviceToken)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in
            NotificationManager.shared.handleRegistrationError(error)
        }
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Handle remote notification when app receives push while running
        print("📬 Received remote notification: \(userInfo)")

        // Process notification payload
        if let notificationType = userInfo["type"] as? String {
            handleRemoteNotification(type: notificationType, data: userInfo)
            completionHandler(.newData)
        } else {
            completionHandler(.noData)
        }
    }

    private func handleRemoteNotification(type: String, data: [AnyHashable: Any]) {
        Task { @MainActor in
            switch type {
            case "uv_alert":
                // Handle UV alert from server
                print("🌞 UV Alert received")
            case "body_spot_reminder":
                // Handle body spot tracker reminder
                print("🔍 Body spot tracker reminder received")
            case "streak_milestone":
                // Handle streak milestone
                print("🔥 Streak milestone received")
            default:
                print("📬 Unknown notification type: \(type)")
            }
        }
    }
}
