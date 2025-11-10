import SwiftUI

struct SpotTimelineView: View {
    let location: BodyLocation
    let spots: [BodySpot]
    let onAddNew: () -> Void
    let onClose: () -> Void
    let onSpotTap: (BodySpot) -> Void

    var sortedSpots: [BodySpot] {
        spots.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Spot History")
                    .font(.headline)
                    .fontWeight(.bold)

                Spacer()

                HStack(spacing: 8) {
                    Button(action: onAddNew) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.footnote)
                            Text("Add Log")
                                .font(.footnote)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.orange)
                        .cornerRadius(20)
                    }

                    Button(action: onClose) {
                        Image(systemName: "chevron.down")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Color(.systemGray5))
                            .cornerRadius(12)
                    }
                }
            }
            .padding()

            // Timeline
            if spots.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)

                    Text("No scans yet")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Add your first scan to start tracking this spot")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button(action: onAddNew) {
                        Text("Add First Scan")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: 200)
                            .background(Color.orange)
                            .cornerRadius(12)
                    }
                }
                .frame(maxHeight: .infinity)
                .padding()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Array(sortedSpots.enumerated()), id: \.element.id) { index, spot in
                            TimelineCard(
                                spot: spot,
                                isLatest: index == 0,
                                onTap: { onSpotTap(spot) }
                            )
                        }

                        // Add new button at end
                        Button(action: onAddNew) {
                            VStack(spacing: 0) {
                                // Spacer to align with cards that have badges
                                Spacer()
                                    .frame(height: 25)
                                
                                ZStack {
                                    Circle()
                                        .strokeBorder(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [5]))
                                        .frame(width: 60, height: 60)

                                    Image(systemName: "plus")
                                        .font(.title2)
                                        .foregroundColor(.orange)
                                }

                                Text("Add New")
                                    .font(.footnote)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)
                                    .lineLimit(1)
                                    .fixedSize()
                                    .padding(.top, 8)
                            }
                            .frame(width: 90)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 0)
                    .padding(.bottom, 40)
                }
            }
        }
    }
}

struct TimelineCard: View {
    let spot: BodySpot
    let isLatest: Bool
    let onTap: () -> Void
    
    @State private var loadedImage: UIImage?
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Latest badge - positioned above circle
                if isLatest {
                    Text("Latest")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green)
                        .cornerRadius(10)
                        .padding(.bottom, 6)
                } else {
                    // Spacer to maintain alignment when no badge
                    Spacer()
                        .frame(height: 25)
                }
                
                // Image circle
                ZStack {
                    if let image = loadedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .strokeBorder(isLatest ? Color.orange : Color(.systemGray4), lineWidth: 2)
                            )
                    } else if isLoading {
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 60, height: 60)
                            .overlay(
                                ProgressView()
                                    .tint(.orange)
                            )
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 60, height: 60)
                            .overlay(
                                Image(systemName: loadFailed ? "exclamationmark.triangle" : "photo")
                                    .font(.title3)
                                    .foregroundColor(loadFailed ? .orange : .gray)
                            )
                    }
                }

                // Date labels
                VStack(spacing: 4) {
                    HStack(spacing: 2) {
                        Text("\(spot.createdAt.formatted(.dateTime.day()))")
                            .font(.system(.footnote, design: .rounded))
                            .fontWeight(.bold)
                        
                        Text("\(spot.createdAt.formatted(.dateTime.month(.abbreviated)))")
                            .font(.system(.footnote, design: .rounded))
                            .fontWeight(.bold)
                    }
                    .lineLimit(1)
                    .fixedSize()

                    Text("\(spot.createdAt.formatted(.dateTime.year()))")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .padding(.top, 8)
            }
            .frame(width: 90)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let url = URL(string: spot.imageUrl) else {
            isLoading = false
            loadFailed = true
            return
        }
        
        Task {
            do {
                // Try to download via Supabase SDK for authenticated access
                let pathComponents = url.pathComponents
                if let filePathIndex = pathComponents.firstIndex(of: "body-scans"),
                   filePathIndex + 1 < pathComponents.count {
                    let filePath = pathComponents[(filePathIndex + 1)...].joined(separator: "/")
                    
                    let data = try await SupabaseManager.shared.client.storage
                        .from("body-scans")
                        .download(path: filePath)
                    
                    if let image = UIImage(data: data) {
                        await MainActor.run {
                            self.loadedImage = image
                            self.isLoading = false
                        }
                        return
                    }
                }
                
                // Fallback to direct URL download
                let (data, response) = try await URLSession.shared.data(from: url)
                
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200,
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        self.loadedImage = image
                        self.isLoading = false
                    }
                } else {
                    await MainActor.run {
                        self.isLoading = false
                        self.loadFailed = true
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.loadFailed = true
                }
            }
        }
    }
}