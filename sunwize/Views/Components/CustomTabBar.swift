import SwiftUI

struct CustomTabBar: View {
    @Binding var selectedTab: Int

    var body: some View {
        HStack(spacing: 0) {
            // Body Spot Tab
            TabBarItem(
                icon: "person.fill",
                title: "Body Spot",
                isSelected: selectedTab == 0,
                action: { selectedTab = 0 }
            )
            .frame(maxWidth: .infinity)

            // Tracking Tab
            TabBarItem(
                icon: "house.fill",
                title: "Tracking",
                isSelected: selectedTab == 1,
                action: { selectedTab = 1 }
            )
            .frame(maxWidth: .infinity)

            // Profile Tab
            TabBarItem(
                icon: "person.circle.fill",
                title: "Profile",
                isSelected: selectedTab == 2,
                action: { selectedTab = 2 }
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.bottom, 15)
        .frame(height: 100)
        .background(Color(.systemBackground)) // Changed to match SpotTimelineView background
        .cornerRadius(24, corners: [.topLeft, .topRight])
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: -2)
    }
}

struct TabBarItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? Color(hex: "#FF9500") : Color.gray.opacity(0.6))

                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Color(hex: "#FF9500") : Color.gray.opacity(0.6))
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
