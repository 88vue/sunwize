import SwiftUI

struct SpotDetailView: View {
    let spot: BodySpot
    let onDelete: () -> Void
    let onClose: () -> Void

    @State private var showingShareSheet = false
    @State private var showingDeleteConfirmation = false
    @StateObject private var imageLoader = ImageLoader()

    var body: some View {
        // Full-screen overlay
        ZStack {
            // Transparent tap-to-dismiss layer
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    onClose()
                }

            // White modal container
            VStack(spacing: 0) {
                // Image section with buttons
                ZStack {
                    // Image
                    if let image = imageLoader.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: Layout.modalWidth, height: Layout.modalImageHeight)
                            .clipped()
                    } else if imageLoader.isLoading {
                        Rectangle()
                            .fill(Color.slate200)
                            .frame(width: Layout.modalWidth, height: Layout.modalImageHeight)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.orange)
                            )
                    } else {
                        Rectangle()
                            .fill(Color.slate200)
                            .frame(width: Layout.modalWidth, height: Layout.modalImageHeight)
                            .overlay(
                                VStack(spacing: Spacing.md) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 60))
                                        .foregroundColor(.gray)
                                    Text("Image not available")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }
                            )
                    }

                    // Close button (top-right)
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Spacer()
                            Button(action: { onClose() }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.3))
                                        .frame(width: 38, height: 38)

                                    Image(systemName: "xmark")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .padding(.top, 12)
                        .padding(.trailing, 12)
                        Spacer()
                    }
                    .frame(width: 334, height: 280)

                    // Delete button (top-left)
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Button(action: { showingDeleteConfirmation = true }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.3))
                                        .frame(width: 38, height: 38)

                                    Image(systemName: "trash")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                }
                            }
                            Spacer()
                        }
                        .padding(.top, 12)
                        .padding(.leading, 12)
                        Spacer()
                    }
                    .frame(width: 334, height: 280)

                    // Share and Download buttons (bottom-left)
                    VStack(spacing: 0) {
                        Spacer()
                        HStack(spacing: 8) {
                            // Share button
                            Button(action: { showingShareSheet = true }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.9))
                                        .frame(width: 34, height: 34)
                                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)

                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 16))
                                        .foregroundColor(Color(hex: "0F172B") ?? .primary)
                                }
                            }

                            // Download button
                            Button(action: { saveImageToPhotos() }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.9))
                                        .frame(width: 34, height: 34)
                                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)

                                    Image(systemName: "arrow.down.to.line")
                                        .font(.system(size: 16))
                                        .foregroundColor(Color(hex: "0F172B") ?? .primary)
                                }
                            }

                            Spacer()
                        }
                        .padding(.leading, 12)
                        .padding(.bottom, 16)
                    }
                    .frame(width: 334, height: 280)
                }
                .frame(width: 334, height: 280)

                // Content section (scrollable)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header with date and evolution badge
                        HStack(alignment: .top, spacing: 0) {
                            // Left side: Spot Analysis and date
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Spot Analysis")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(Color(hex: "0F172B") ?? .primary)
                                    .tracking(-0.44)

                                HStack(spacing: 6) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 14))
                                        .foregroundColor(Color(hex: "62748E") ?? .secondary)

                                    Text("Logged on \(formattedDate)")
                                        .font(.system(size: 16))
                                        .foregroundColor(Color(hex: "62748E") ?? .secondary)
                                        .tracking(-0.31)
                                }
                            }

                            Spacer()

                            // Right side: Evolution badge
                            VStack(spacing: 2) {
                                Text("EVOLUTION")
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundColor(Color(hex: "E17100") ?? .orange)
                                    .tracking(0.62)

                                Text(evolutionStatus)
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(hex: "7B3306") ?? .brown)
                                    .tracking(-0.31)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color(hex: "FFFBEB") ?? Color.yellow.opacity(0.1)) // amber-50
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color(hex: "FEF3C6") ?? Color.yellow.opacity(0.2), lineWidth: 1)
                            )
                            .cornerRadius(14)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                        // ABCDE Assessment section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ABCDE ASSESSMENT")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color(hex: "90A1B9") ?? .secondary)
                                .tracking(0.6)
                                .padding(.horizontal, 20)

                            VStack(spacing: 10) {
                                AssessmentRowNew(
                                    title: "Asymmetry",
                                    value: spot.asymmetry ? "Yes" : "No",
                                    riskColor: getRiskColor(for: "asymmetry")
                                )

                                AssessmentRowNew(
                                    title: "Border",
                                    value: spot.border.rawValue,
                                    riskColor: getRiskColor(for: "border")
                                )

                                AssessmentRowNew(
                                    title: "Color",
                                    value: spot.color.rawValue,
                                    riskColor: getRiskColor(for: "color")
                                )

                                AssessmentRowNew(
                                    title: "Diameter",
                                    value: "\(Int(spot.diameter))mm",
                                    riskColor: getRiskColor(for: "diameter")
                                )
                            }
                            .padding(.horizontal, 20)
                        }

                        // Notes section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NOTES")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color(hex: "90A1B9") ?? .secondary)
                                .tracking(0.6)

                            Text(notesText)
                                .font(.system(size: 15, weight: .regular))
                                .italic()
                                .foregroundColor(Color(hex: "45556C") ?? .secondary)
                                .lineSpacing(11)
                                .tracking(-0.31)
                                .padding(13)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(hex: "F8FAFC") ?? Color.gray.opacity(0.1)) // slate-50
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color(hex: "F1F5F9") ?? Color.gray.opacity(0.2), lineWidth: 1)
                                )
                                .cornerRadius(14)
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .frame(maxHeight: 440)
            }
            .frame(width: 334, height: 720)
            .background(Color.white)
            .cornerRadius(24)
            .shadow(color: Color.black.opacity(0.25), radius: 25, x: 0, y: 25)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let image = imageLoader.image {
                ShareSheet(items: [image])
            } else {
                ShareSheet(items: [])
            }
        }
        .alert("Delete Spot", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                onDelete()
                onClose()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this spot? This action cannot be undone.")
        }
        .onAppear {
            imageLoader.load(from: spot.imageUrl)
        }
    }

    // MARK: - Computed Properties

    private var formattedDate: String {
        return DateFormatters.formatMonthDay(spot.createdAt)
    }

    private var evolutionStatus: String {
        switch spot.evolving {
        case .unchanged:
            return "No"
        case .growing:
            return "Yes"
        case .changing:
            return "Yes"
        }
    }

    private var notesText: String {
        if let notes = spot.notes, !notes.isEmpty {
            return "\"\(notes)\""
        } else {
            return "No notes"
        }
    }

    // MARK: - Helper Functions

    private func getRiskColor(for indicator: String) -> Color {
        // TODO: Implement proper risk assessment logic based on ABCDE criteria
        return Color.success
    }

    private func saveImageToPhotos() {
        guard let image = imageLoader.image else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }
}

// MARK: - Assessment Row Component
struct AssessmentRowNew: View {
    let title: String
    let value: String
    let riskColor: Color

    var body: some View {
        HStack {
            // Left side: colored dot + title
            HStack(spacing: 8) {
                Circle()
                    .fill(riskColor)
                    .frame(width: 8, height: 8)

                Text(title)
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "45556C") ?? .secondary)
                    .tracking(-0.31)
            }

            Spacer()

            // Right side: value
            Text(value)
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "0F172B") ?? .primary)
                .tracking(-0.31)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 13)
        .background(Color(hex: "F8FAFC") ?? Color.gray.opacity(0.1)) // slate-50
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "F1F5F9") ?? Color.gray.opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(14)
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

