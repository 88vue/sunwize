import SwiftUI

struct SpotDetailView: View {
    let spot: BodySpot
    let onDelete: () -> Void
    
    @Environment(\.dismiss) var dismiss
    @State private var showingShareSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var loadedImage: UIImage?
    @State private var isLoadingImage = true

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Image with share button
                    ZStack(alignment: .topTrailing) {
                        if let image = loadedImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 300)
                                .clipped()
                        } else if isLoadingImage {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 300)
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(1.5)
                                        .tint(.orange)
                                )
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 300)
                                .overlay(
                                    VStack(spacing: 12) {
                                        Image(systemName: "photo")
                                            .font(.system(size: 60))
                                            .foregroundColor(.gray)
                                        Text("Image not available")
                                            .font(.body)
                                            .foregroundColor(.secondary)
                                    }
                                )
                        }
                        
                        // Share button overlay
                        Button(action: { showingShareSheet = true }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .padding()
                    }

                    // Date
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.orange)
                        Text(spot.createdAt, format: .dateTime.month().day().year())
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.horizontal)

                    // ABCDE Assessment
                    VStack(alignment: .leading, spacing: 16) {
                        Text("ABCDE Assessment")
                            .font(.headline)

                        AssessmentRow(
                            title: "Asymmetry",
                            value: spot.asymmetry ? "Yes" : "No",
                            concerning: spot.asymmetry
                        )

                        AssessmentRow(
                            title: "Border",
                            value: spot.border.rawValue,
                            concerning: spot.border == .irregular
                        )

                        AssessmentRow(
                            title: "Color",
                            value: spot.color.rawValue,
                            concerning: spot.color == .varied
                        )

                        AssessmentRow(
                            title: "Diameter",
                            value: "\(Int(spot.diameter)) mm",
                            concerning: spot.diameter > 6
                        )

                        AssessmentRow(
                            title: "Evolution",
                            value: spot.evolving.rawValue,
                            concerning: spot.evolving == .grown
                        )

                        // Risk indicator
                        let riskScore = calculateRiskScore()
                        if riskScore > 2 {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(riskScore > 3 ? .red : .orange)

                                Text(riskScore > 3 ?
                                     "High-risk features detected. Consult a dermatologist." :
                                     "Some concerning features. Monitor closely.")
                                    .font(.caption)
                                    .foregroundColor(riskScore > 3 ? .red : .orange)
                            }
                            .padding()
                            .background((riskScore > 3 ? Color.red : Color.orange).opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .padding(.horizontal)

                    // Description
                    if let description = spot.description, !description.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Description", systemImage: "text.alignleft")
                                .font(.headline)

                            Text(description)
                                .font(.body)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(16)
                        .padding(.horizontal)
                    }

                    // Notes
                    if let notes = spot.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Notes", systemImage: "note.text")
                                .font(.headline)

                            Text(notes)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(16)
                        .padding(.horizontal)
                    }

                    // Actions
                    HStack(spacing: 16) {
                        Button(action: { showingShareSheet = true }) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(12)
                        }

                        Button(action: { showingDeleteConfirmation = true }) {
                            Label("Delete", systemImage: "trash")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Spot Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: [generateShareText()])
        }
        .alert("Delete Spot", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                onDelete()
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this spot? This action cannot be undone.")
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let url = URL(string: spot.imageUrl) else {
            isLoadingImage = false
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
                            self.isLoadingImage = false
                        }
                        return
                    }
                }
                
                await MainActor.run {
                    self.isLoadingImage = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingImage = false
                }
            }
        }
    }

    private func calculateRiskScore() -> Int {
        var score = 0
        if spot.asymmetry { score += 1 }
        if spot.border == .irregular { score += 1 }
        if spot.color == .varied { score += 1 }
        if spot.diameter > 6 { score += 1 }
        if spot.evolving == .grown { score += 1 }
        return score
    }

    private func generateShareText() -> String {
        """
        Body Spot Assessment
        Date: \(spot.createdAt.formatted())
        Location: \(spot.bodyPart)

        ABCDE Assessment:
        - Asymmetry: \(spot.asymmetry ? "Yes" : "No")
        - Border: \(spot.border.rawValue)
        - Color: \(spot.color.rawValue)
        - Diameter: \(Int(spot.diameter)) mm
        - Evolution: \(spot.evolving.rawValue)

        \(spot.description ?? "")

        Tracked with Sunwize App
        """
    }
}

struct AssessmentRow: View {
    let title: String
    let value: String
    let concerning: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(concerning ? .orange : .primary)

            if concerning {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
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