import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 1
    @EnvironmentObject var profileViewModel: ProfileViewModel
    @EnvironmentObject var locationManager: LocationManager

    var body: some View {
        TabView(selection: $selectedTab) {
            BodyScanView()
                .tabItem {
                    Label("Body Scan", systemImage: "camera.viewfinder")
                }
                .tag(0)

            UVTrackingView()
                .tabItem {
                    Label("Tracking", systemImage: "sun.max.fill")
                }
                .tag(1)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(2)
        }
        .accentColor(.orange)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToBodyScan)) { _ in
            selectedTab = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToUVTracking)) { _ in
            selectedTab = 1
        }
    }
}