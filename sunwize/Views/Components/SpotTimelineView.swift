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

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 9999)
                .fill(Color(.systemGray3))
                .frame(width: Layout.dragHandleWidth, height: Layout.dragHandleHeight)
                .padding(.top, Spacing.BottomSheet.dragHandleTop)
                .padding(.bottom, Spacing.BottomSheet.dragHandleBottom)

            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Spot History")
                        .font(.system(size: Typography.title3, weight: .bold))
                        .foregroundColor(.primary)

                    Text("\(spots.count) spot\(spots.count == 1 ? "" : "s")")
                        .font(.system(size: Typography.subheadline))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onClose) {
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

            // Content - Horizontal scrolling timeline
            if spots.isEmpty {
                VStack(spacing: Spacing.base) {
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
                }
                .frame(height: 120)
                .padding()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.md) {
                        ForEach(sortedSpots, id: \.id) { spot in
                            GridImageCard(
                                spot: spot,
                                onTap: { onSpotTap(spot) }
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.xl)
                }
                .frame(height: Layout.timelineCardHeight)
            }

            // Add New Photo Button
            Button(action: onAddNew) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: Typography.body))

                    Text("Add New Photo")
                        .font(.system(size: Typography.body, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: Layout.buttonHeight)
                .background(Color.orange)
                .cornerRadius(CornerRadius.base)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.BottomSheet.contentToButton)
            .padding(.bottom, Spacing.BottomSheet.buttonBottom)
        }
        .background(Color(.systemBackground))
        .cornerRadius(CornerRadius.lg, corners: [.topLeft, .topRight])
        .shadow(.medium)
        .frame(height: Layout.timelineHeight)
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
                        onClose()
                    } else {
                        withAnimation {
                            dragOffset = 0
                        }
                    }
                }
        )
    }
}

struct GridImageCard: View {
    let spot: BodySpot
    let onTap: () -> Void

    @StateObject private var imageLoader = ImageLoader()

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: Spacing.sm) {
                // Image Container
                ZStack {
                    // Background
                    Color(.systemGray5)

                    // Image
                    if let image = imageLoader.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: Layout.thumbnailSize, height: Layout.thumbnailSize)
                            .clipped()
                    } else if imageLoader.isLoading {
                        ProgressView()
                            .tint(.orange)
                            .frame(width: Layout.thumbnailSize, height: Layout.thumbnailSize)
                    } else {
                        Image(systemName: imageLoader.loadFailed ? "exclamationmark.triangle" : "photo")
                            .font(.title)
                            .foregroundColor(imageLoader.loadFailed ? .orange : .gray)
                            .frame(width: Layout.thumbnailSize, height: Layout.thumbnailSize)
                    }
                }
                .frame(width: Layout.thumbnailSize, height: Layout.thumbnailSize)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.base))

                // Date Label
                Text(DateFormatters.formatMonthDay(spot.createdAt))
                    .font(.system(size: Typography.footnote, weight: .medium))
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            imageLoader.load(from: spot.imageUrl)
        }
    }
}
