import SwiftUI

/// Circular progress ring showing vitamin D completion percentage
struct VitaminDProgressRing: View {
    // MARK: - Properties
    let progress: Double // 0.0 to 1.0

    @State private var animatedProgress: Double = 0

    // MARK: - Body
    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.vitaminDProgressGray, lineWidth: Layout.VitaminD.progressRingLineWidth)

            // Progress ring
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    Color.vitaminDPrimary,
                    style: StrokeStyle(
                        lineWidth: Layout.VitaminD.progressRingLineWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))

            // Center content
            VStack(spacing: 4) {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.black)

                Text("Complete")
                    .font(.system(size: 14))
                    .foregroundColor(.slate600)
            }
        }
        .frame(width: Layout.VitaminD.progressRingSize, height: Layout.VitaminD.progressRingSize)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8)) {
                animatedProgress = min(progress, 1.0)
            }
        }
        .onChange(of: progress) { newValue in
            withAnimation(.easeInOut(duration: 0.5)) {
                animatedProgress = min(newValue, 1.0)
            }
        }
    }
}

// MARK: - Preview
#Preview("Vitamin D Progress Ring") {
    VStack(spacing: 40) {
        VitaminDProgressRing(progress: 0.25)
        VitaminDProgressRing(progress: 0.5)
        VitaminDProgressRing(progress: 0.75)
        VitaminDProgressRing(progress: 1.0)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
