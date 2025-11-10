import SwiftUI
import SceneKit

// MARK: - Marker Model
struct SpotMarker: Identifiable {
    let id: String
    let position: SIMD3<Float>
    let bodyPart: String
    let spotCount: Int
}

// MARK: - 3D Body Model View

struct BodyModel3DView: UIViewRepresentable {
    let spotMarkers: [SpotMarker]
    let isInteractive: Bool
    let onModelTap: (SIMD3<Float>) -> Void
    let onSpotTap: (SIMD3<Float>, String) -> Void
    
    @Binding var isLoading: Bool
    
    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.backgroundColor = UIColor.systemGroupedBackground // Match BodyScanView background
        sceneView.autoenablesDefaultLighting = true
        sceneView.allowsCameraControl = true
        
        // Configure camera for continuous 360° rotation (no angle restrictions)
        sceneView.defaultCameraController.interactionMode = .orbitTurntable
        sceneView.defaultCameraController.maximumVerticalAngle = 90  // Prevent flipping over top/bottom
        sceneView.defaultCameraController.minimumVerticalAngle = -90
        // Don't set horizontal angles - this allows continuous 360° horizontal rotation
        
        // Disable two-finger panning while keeping one-finger rotation
        // Find the pan gesture recognizer and limit it to one finger only
        if let panGesture = sceneView.gestureRecognizers?.first(where: { $0 is UIPanGestureRecognizer }) as? UIPanGestureRecognizer {
            panGesture.maximumNumberOfTouches = 1  // Only allow one finger (rotation), disable two-finger panning
        }
        
        // Add gesture recognizers
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        let doubleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        
        sceneView.addGestureRecognizer(tapGesture)
        sceneView.addGestureRecognizer(doubleTapGesture)
        
        // Make single tap wait for double tap to fail
        tapGesture.require(toFail: doubleTapGesture)
        
        context.coordinator.sceneView = sceneView
        
        // Load the scene asynchronously
        DispatchQueue.main.async {
            isLoading = true
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let scene = self.loadBodyModelScene() {
                DispatchQueue.main.async {
                    sceneView.scene = scene
                    isLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    sceneView.scene = self.createFallbackScene()
                    isLoading = false
                }
            }
        }
        
        return sceneView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        // Update markers
        updateMarkers(in: uiView.scene, context: context)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Scene Loading
    private func loadBodyModelScene() -> SCNScene? {
        // Load USDZ file (Apple's recommended format for iOS)
        guard let usdzURL = Bundle.main.url(forResource: "FinalBaseMesh", withExtension: "usdz") else {
            print("⚠️ Could not find FinalBaseMesh.usdz in bundle")
            return nil
        }
        
        
        do {
            let scene = try SCNScene(url: usdzURL, options: nil)
            
            // Apply gray material to all geometry for better visibility
            applyGrayMaterial(to: scene.rootNode)
            
            setupScene(scene)
            return scene
        } catch {
            print("❌ Error loading USDZ: \(error)")
            return nil
        }
    }
    
    private func applyGrayMaterial(to node: SCNNode) {
        // Apply material to this node's geometry if it has one
        if let geometry = node.geometry {
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0) // Medium gray
            material.lightingModel = .physicallyBased
            material.metalness.contents = 0.0
            material.roughness.contents = 0.7
            
            // Replace all materials with our gray material
            geometry.materials = [material]
        }
        
        // Recursively apply to all child nodes
        for child in node.childNodes {
            applyGrayMaterial(to: child)
        }
    }
    
    private func setupScene(_ scene: SCNScene) {
        // Position the model in the correct place
        // These values match the Expo version's positioning
        if let modelNode = scene.rootNode.childNodes.first {
            modelNode.position = SCNVector3(0, -10, -23)
            modelNode.scale = SCNVector3(1, 1, 1)
        }
        
        // Configure lighting
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 600
        scene.rootNode.addChildNode(ambientLight)
        
        let directionalLight1 = SCNNode()
        directionalLight1.light = SCNLight()
        directionalLight1.light?.type = .directional
        directionalLight1.light?.intensity = 800
        directionalLight1.position = SCNVector3(5, 5, 5)
        scene.rootNode.addChildNode(directionalLight1)
        
        let directionalLight2 = SCNNode()
        directionalLight2.light = SCNLight()
        directionalLight2.light?.type = .directional
        directionalLight2.light?.intensity = 400
        directionalLight2.position = SCNVector3(-5, -5, 5)
        scene.rootNode.addChildNode(directionalLight2)
        
        // Setup camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 60
        cameraNode.position = SCNVector3(0, 0, 2)
        cameraNode.look(at: SCNVector3(0, 0, -23))
        scene.rootNode.addChildNode(cameraNode)
    }
    
    private func createFallbackScene() -> SCNScene {
        let scene = SCNScene()
        
        // Create a simple human figure as fallback
        let bodyGeometry = SCNCylinder(radius: 0.5, height: 3)
        bodyGeometry.firstMaterial?.diffuse.contents = UIColor.systemGray4
        let bodyNode = SCNNode(geometry: bodyGeometry)
        bodyNode.position = SCNVector3(0, 0, -23)
        bodyNode.name = "body"
        
        let headGeometry = SCNSphere(radius: 0.35)
        headGeometry.firstMaterial?.diffuse.contents = UIColor.systemGray4
        let headNode = SCNNode(geometry: headGeometry)
        headNode.position = SCNVector3(0, 1.85, 0)
        headNode.name = "head"
        
        bodyNode.addChildNode(headNode)
        scene.rootNode.addChildNode(bodyNode)
        
        setupScene(scene)
        
        return scene
    }
    
    // MARK: - Marker Management
    private func updateMarkers(in scene: SCNScene?, context: Context) {
        guard let scene = scene else { return }
        
        // Find the model node (first child that's not a light or camera)
        guard let modelNode = scene.rootNode.childNodes.first(where: { node in
            node.geometry != nil || !node.childNodes.isEmpty && node.light == nil && node.camera == nil
        }) else {
            return
        }
        
        // Remove existing markers from the model node
        modelNode.childNodes
            .filter { $0.name == "marker" }
            .forEach { $0.removeFromParentNode() }
        
        // Add new markers as children of the model node
        // This way they inherit the model's transform and position correctly
        for marker in spotMarkers {
            let markerNode = createMarkerNode(for: marker)
            modelNode.addChildNode(markerNode)
            context.coordinator.markerNodes[marker.id] = markerNode
        }
    }
    
    private func createMarkerNode(for marker: SpotMarker) -> SCNNode {
        let geometry = SCNSphere(radius: 0.12)
        
        // Orange color like the Expo version
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.systemOrange
        material.emission.contents = UIColor.systemOrange
        material.emission.intensity = 0.3
        geometry.materials = [material]
        
        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3(marker.position.x, marker.position.y, marker.position.z)
        node.name = "marker"
        
        // Store marker data
        node.setValue(marker.id, forKey: "markerId")
        node.setValue(marker.bodyPart, forKey: "bodyPart")
        
        return node
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject {
        let parent: BodyModel3DView
        weak var sceneView: SCNView?
        var markerNodes: [String: SCNNode] = [:]
        var pendingTapTime: Date?
        let doubleTapThreshold: TimeInterval = 0.6
        
        init(_ parent: BodyModel3DView) {
            self.parent = parent
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let sceneView = sceneView else { return }
            let location = gesture.location(in: sceneView)
            let hitResults = sceneView.hitTest(location, options: [:])
            
            // Check if we tapped a marker
            if let hit = hitResults.first(where: { $0.node.name == "marker" }) {
                // Marker positions are in model's local space, so we can use them directly
                let position = hit.node.position
                let coordinates = SIMD3<Float>(position.x, position.y, position.z)
                
                if let bodyPart = hit.node.value(forKey: "bodyPart") as? String {
                    parent.onSpotTap(coordinates, bodyPart)
                }
            }
        }
        
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let sceneView = sceneView, parent.isInteractive else { return }
            let location = gesture.location(in: sceneView)
            let hitResults = sceneView.hitTest(location, options: [:])
            
            // Ignore if tapped on a marker - let single tap handle that
            if hitResults.first(where: { $0.node.name == "marker" }) != nil {
                return
            }
            
            // Get the first hit on the body model
            if let hit = hitResults.first {
                let worldCoordinates = hit.worldCoordinates
                
                // Find the model node and convert to its local space
                // This ensures coordinates are relative to the model, not world space
                if let modelNode = sceneView.scene?.rootNode.childNodes.first(where: { node in
                    (node.geometry != nil || !node.childNodes.isEmpty) && node.light == nil && node.camera == nil
                }) {
                    let localCoordinates = modelNode.convertPosition(worldCoordinates, from: sceneView.scene?.rootNode)
                    let coordinates = SIMD3<Float>(localCoordinates.x, localCoordinates.y, localCoordinates.z)
                    parent.onModelTap(coordinates)
                } else {
                    // Fallback to world coordinates if model node not found
                    let coordinates = SIMD3<Float>(worldCoordinates.x, worldCoordinates.y, worldCoordinates.z)
                    parent.onModelTap(coordinates)
                }
            }
        }
    }
}

// MARK: - Preview Provider
#if DEBUG
struct BodyModel3DView_Previews: PreviewProvider {
    static var previews: some View {
        BodyModel3DView(
            spotMarkers: [
                SpotMarker(id: "1", position: SIMD3<Float>(0, 1, 0), bodyPart: "Chest", spotCount: 2),
                SpotMarker(id: "2", position: SIMD3<Float>(0.5, 0, 0), bodyPart: "Left Arm", spotCount: 1)
            ],
            isInteractive: true,
            onModelTap: { coords in
                print("Model tapped at: \(coords)")
            },
            onSpotTap: { coords, bodyPart in
                print("Spot tapped at: \(coords), body part: \(bodyPart)")
            },
            isLoading: .constant(false)
        )
    }
}
#endif

