import SwiftUI
import SceneKit

enum BottomViewMode {
    case none
    case timeline
    case form
}

struct LocationData {
    let coordinates: SIMD3<Float>
    let bodyPart: String
    var spots: [BodySpot]
}

class BodySpotUIState: ObservableObject {
    @Published var bottomViewMode: BottomViewMode = .none
    @Published var selectedLocation: LocationData?
    @Published var selectedSpot: BodySpot?
    
    func closeBottomView() {
        withAnimation {
            bottomViewMode = .none
        }
        selectedLocation = nil
    }
}
