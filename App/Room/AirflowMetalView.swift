import SwiftUI
import MetalKit
import MechanicalCore

enum RoomFlowDisplay: String, CaseIterable, Identifiable {
    case dye = "Tracers", speed = "Speed", curl = "Vorticity"
    var id: String { rawValue }
    var index: Float { switch self { case .dye: 0; case .speed: 1; case .curl: 2 } }
}

@MainActor private enum RoomMetalResources {
    static let device = MTLCreateSystemDefaultDevice()
    static let pipeline: MTLRenderPipelineState? = {
        guard let device, let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "roomVertex"),
              let fragment = library.makeFunction(name: "roomFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }()
}

struct AirflowFieldView: View {
    var frame: RoomFlowFrame
    var referenceSpeed: Double
    var display: RoomFlowDisplay
    var reducedMotion: Bool
    var tilt: SIMD2<Float> = .zero
    static var isMetalAvailable: Bool { RoomMetalResources.pipeline != nil }

    var body: some View {
        if Self.isMetalAvailable {
            AirflowMetalView(frame: frame, referenceSpeed: referenceSpeed, display: display,
                             reducedMotion: reducedMotion, tilt: tilt)
        } else {
            SoftwareAirflowView(frame: frame, referenceSpeed: referenceSpeed, display: display)
                .overlay(alignment: .bottom) {
                    Text("Software flow view · Metal unavailable")
                        .font(.caption2).padding(6)
                        .background(ToyTheme.background, in: Capsule())
                        .padding(.bottom, 30)
                }
        }
    }
}

private struct SoftwareAirflowView: View {
    var frame: RoomFlowFrame
    var referenceSpeed: Double
    var display: RoomFlowDisplay

    var body: some View {
        Canvas { context, size in
            let cellWidth = size.width / CGFloat(frame.width)
            let cellHeight = size.height / CGFloat(frame.height)
            for y in 0..<frame.height {
                for x in 0..<frame.width {
                    let index = (x + y * frame.width) * 4
                    let vx = Double(frame.pixels[index]), vy = Double(frame.pixels[index + 1])
                    let tracer = Double(frame.pixels[index + 2])
                    let solid = frame.pixels[index + 3] > 0.5
                    let speed = min(1, hypot(vx, vy) / max(1, referenceSpeed * 1.6))
                    let rect = CGRect(x: CGFloat(x) * cellWidth, y: CGFloat(frame.height - y - 1) * cellHeight,
                                      width: cellWidth + 0.5, height: cellHeight + 0.5)
                    let color: Color
                    if solid { color = ToyTheme.muted.opacity(0.8) }
                    else if display == .dye { color = ToyTheme.cyan.opacity(0.08 + tracer * 0.7) }
                    else if display == .speed { color = speed > 0.7 ? ToyTheme.copper.opacity(speed) : ToyTheme.cyan.opacity(speed) }
                    else {
                        let left = max(0, x - 1), right = min(frame.width - 1, x + 1)
                        let down = max(0, y - 1), up = min(frame.height - 1, y + 1)
                        let spin = (frame.pixels[(right + y * frame.width) * 4 + 1] - frame.pixels[(left + y * frame.width) * 4 + 1])
                            - (frame.pixels[(x + up * frame.width) * 4] - frame.pixels[(x + down * frame.width) * 4])
                        color = (spin > 0 ? ToyTheme.copper : ToyTheme.cyan).opacity(Double(min(0.9, abs(spin) / 3)))
                    }
                    context.fill(Path(rect), with: .color(color))
                    if !solid, x % 6 == 3, y % 6 == 3, speed > 0.01 {
                        let center = CGPoint(x: rect.midX, y: rect.midY)
                        let scale = 9 / max(1, hypot(vx, vy))
                        let tip = CGPoint(x: center.x + vx * scale, y: center.y - vy * scale)
                        var vector = Path()
                        vector.move(to: center); vector.addLine(to: tip)
                        context.stroke(vector, with: .color(ToyTheme.ink.opacity(0.8)), lineWidth: 1)
                    }
                }
            }
        }.background(ToyTheme.background)
    }
}

struct AirflowMetalView: UIViewRepresentable {
    var frame: RoomFlowFrame
    var referenceSpeed: Double
    var display: RoomFlowDisplay
    var reducedMotion: Bool
    var tilt: SIMD2<Float> = .zero

    func makeCoordinator() -> Renderer { Renderer() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.02, green: 0.04, blue: 0.06, alpha: 1)
        view.framebufferOnly = true
        view.delegate = context.coordinator
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.update(frame: frame, referenceSpeed: referenceSpeed,
                                   display: display.index, reducedMotion: reducedMotion, tilt: tilt)
        view.setNeedsDisplay()
    }

    static func dismantleUIView(_ view: MTKView, coordinator: Renderer) {
        view.isPaused = true
        view.delegate = nil
    }

    @MainActor final class Renderer: NSObject, MTKViewDelegate {
        let device: MTLDevice?
        private let queue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var field: MTLTexture?
        private struct Uniforms {
            var field = SIMD4<Float>(5, 0, 0, 0)
            var optics = SIMD4<Float>.zero
        }
        private var uniforms = Uniforms()
        private var previousPixels: [Float] = []

        override init() {
            let device = RoomMetalResources.device
            self.device = device
            queue = device?.makeCommandQueue()
            super.init()
            pipeline = RoomMetalResources.pipeline
        }

        func update(frame: RoomFlowFrame, referenceSpeed: Double, display: Float, reducedMotion: Bool, tilt: SIMD2<Float>) {
            guard let device else { return }
            // Each snapshot owns its texture; queued GPU work never reads a CPU-mutated field.
            if field == nil || field?.width != frame.width || field?.height != frame.height || previousPixels != frame.pixels {
              let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float,
                width: frame.width, height: frame.height, mipmapped: false)
              descriptor.storageMode = .shared
              descriptor.usage = .shaderRead
              field = device.makeTexture(descriptor: descriptor)
              frame.pixels.withUnsafeBytes { bytes in
                guard let pointer = bytes.baseAddress else { return }
                field?.replace(region: MTLRegionMake2D(0, 0, frame.width, frame.height),
                    mipmapLevel: 0, withBytes: pointer, bytesPerRow: frame.width * 4 * MemoryLayout<Float>.stride)
              }
              previousPixels = frame.pixels
            }
            uniforms.field = SIMD4(Float(referenceSpeed), display, Float(frame.time), reducedMotion ? 1 : 0)
            uniforms.optics = reducedMotion ? .zero : SIMD4(tilt.x, tilt.y, 0, 0)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let pipeline, let field, let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor,
                  let command = queue?.makeCommandBuffer(),
                  let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else { return }
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(field, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            command.present(drawable)
            command.commit()
        }
    }
}
