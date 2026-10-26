import AppKit
import Foundation
import ModelIO
import SceneKit
import SceneKit.ModelIO

/// Offscreen SceneKit snapshot of a ModelIO asset, auto-framed from its bounding box.
enum Model3DPreview {
    static let side: CGFloat = 1024

    static func render(_ asset: MDLAsset, to url: URL) throws {
        let scene = SCNScene(mdlAsset: asset)
        let (low, high) = scene.rootNode.boundingBox
        let size = [Double(high.x - low.x), Double(high.y - low.y), Double(high.z - low.z)]
        let diagonal = size.map { $0 * $0 }.reduce(0, +).squareRoot()
        guard diagonal.isFinite, diagonal > 0 else {
            throw ConversionError.unsupportedInput(L10n.text("Mô hình trống"))
        }
        let center = SCNVector3(x: (low.x + high.x) / 2, y: (low.y + high.y) / 2, z: (low.z + high.z) / 2)

        let camera = SCNCamera()
        camera.fieldOfView = 40
        camera.zNear = diagonal / 100
        camera.zFar = diagonal * 20
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        let distance = CGFloat(diagonal * 1.2)
        cameraNode.position = SCNVector3(x: center.x + distance * 0.55, y: center.y + distance * 0.45, z: center.z + distance)
        scene.rootNode.addChildNode(cameraNode)
        cameraNode.look(at: center)
        scene.background.contents = NSColor(calibratedWhite: 0.16, alpha: 1)

        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ConversionError.failed(L10n.text("Không có GPU để dựng ảnh xem trước"))
        }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = cameraNode
        renderer.autoenablesDefaultLighting = true
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: side, height: side), antialiasingMode: .multisampling4X)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            throw ConversionError.failed(L10n.text("Không dựng được ảnh xem trước"))
        }
        try png.write(to: url)
    }
}
