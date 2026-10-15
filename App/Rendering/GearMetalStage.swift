import SwiftUI
import MetalKit
import MechanicalCore
import simd

@MainActor private enum GearMetalResources {
    static let device = MTLCreateSystemDefaultDevice()
    static let sampleCount: Int = device?.supportsTextureSampleCount(4) == true ? 4 : 1
    static let scene: MTLRenderPipelineState? = {
        guard let device, let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "gearVertex"),
              let fragment = library.makeFunction(name: "gearFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Mechanical Toy · chrome geometry"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.rasterSampleCount = sampleCount
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }()
    static let optics: MTLRenderPipelineState? = {
        guard let device, let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "gearOpticsVertex"),
              let fragment = library.makeFunction(name: "gearOpticsFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Mechanical Toy · refractive cover"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }()
    static let depth: MTLDepthStencilState? = {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .lessEqual
        descriptor.isDepthWriteEnabled = true
        return device?.makeDepthStencilState(descriptor: descriptor)
    }()
}

/// Depth-tested procedural geometry viewed through a sampled optical cover.
/// The caller supplies phase and attitude; there is no autonomous display loop.
struct GearMetalStage: View {
    var kind: GearKind
    var inputs: GearTransmissionInputs
    var phase: Double
    var tilt: SIMD2<Float>
    var orbit: SIMD2<Float>
    var exploded: Double
    var hologram: Bool
    var reducedMotion: Bool
    var reducedTransparency: Bool = false

    static var isMetalAvailable: Bool {
        GearMetalResources.scene != nil && GearMetalResources.optics != nil && GearMetalResources.depth != nil
    }

    var body: some View {
        Group {
            if Self.isMetalAvailable {
                NativeGearMetalView(kind: kind, inputs: inputs, phase: phase, tilt: tilt, orbit: orbit,
                                    exploded: exploded, hologram: hologram, reducedMotion: reducedMotion,
                                    reducedTransparency: reducedTransparency)
            } else {
                GearOutlineFallback(kind: kind, inputs: inputs, phase: phase)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Three dimensional \(kind.title)")
        .accessibilityValue(Self.isMetalAvailable ? (exploded > 0.1 ? "Separated parts, shaft axes visible" : "Assembled transmission") : "Simplified outline, Metal unavailable")
        .accessibilityHint("Drag to orbit the mechanism. Enable motion to move its reflections and optical cover with your iPhone.")
    }
}

private struct GearOutlineFallback: View {
    var kind: GearKind
    var inputs: GearTransmissionInputs
    var phase: Double

    var body: some View {
        Canvas { context, size in
            let values = GearTransmission.normalizedInputs(kind: kind, inputs: inputs)
            let radius = min(size.width * 0.28, size.height * 0.28)
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            for (index, count) in [Int(values.driverTeeth), Int(values.drivenTeeth)].enumerated() {
                let r = radius * (index == 0 ? 0.62 : 1)
                let x = centre.x + (index == 0 ? -radius : radius * 0.62)
                let p = CGPoint(x: x, y: centre.y)
                var path = Path()
                let angle = (phase.isFinite ? phase : 0) * (index == 0 ? 1 : -values.driverTeeth / values.drivenTeeth)
                for tooth in 0..<(count * 4) {
                    let theta = Double(tooth) * 2 * .pi / Double(count * 4) + angle
                    let gearRadius = r * (tooth % 4 < 2 ? 1.08 : 0.94)
                    let point = CGPoint(x: p.x + cos(theta) * gearRadius, y: p.y + sin(theta) * gearRadius)
                    if tooth == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath()
                context.fill(path, with: .color(Color(white: 0.16)))
                context.stroke(path, with: .color(Color.cyan.opacity(0.7)), lineWidth: 1.5)
                context.stroke(Path(ellipseIn: CGRect(x: p.x - r * 0.23, y: p.y - r * 0.23,
                                                       width: r * 0.46, height: r * 0.46)),
                               with: .color(Color(white: 0.75)), lineWidth: 2)
            }
        }
        .background(Color(red: 0.02, green: 0.03, blue: 0.055))
        .overlay(alignment: .bottom) {
            Text("Metal 3D unavailable · simplified gear outline")
                .font(.caption2).foregroundStyle(.secondary).padding(10)
        }
    }
}

private struct GearSceneUniforms {
    var viewProjection: simd_float4x4
    var model: simd_float4x4
    var cameraAndTime: SIMD4<Float>
    var tiltAndAspect: SIMD4<Float>
    var material: SIMD4<Float>
    var features: SIMD4<Float>
}
private struct GearOpticsUniforms {
    var optics: SIMD4<Float>
    var settings: SIMD4<Float>
    var viewport: SIMD4<Float>
}

private struct NativeGearMetalView: UIViewRepresentable {
    var kind: GearKind
    var inputs: GearTransmissionInputs
    var phase: Double
    var tilt: SIMD2<Float>
    var orbit: SIMD2<Float>
    var exploded: Double
    var hologram: Bool
    var reducedMotion: Bool
    var reducedTransparency: Bool

    func makeCoordinator() -> Renderer { Renderer() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: GearMetalResources.device)
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.framebufferOnly = true
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.025, green: 0.037, blue: 0.060, alpha: 1)
        view.delegate = context.coordinator
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.update(kind: kind, inputs: inputs, phase: phase, tilt: tilt, orbit: orbit,
                                   exploded: exploded, hologram: hologram, reducedMotion: reducedMotion,
                                   reducedTransparency: reducedTransparency)
        view.setNeedsDisplay()
    }

    static func dismantleUIView(_ view: MTKView, coordinator: Renderer) {
        view.isPaused = true
        view.delegate = nil
        coordinator.releaseTargets()
    }

    @MainActor final class Renderer: NSObject, MTKViewDelegate {
        private struct GPUPart {
            let buffer: MTLBuffer
            let vertexCount: Int
            let transform: simd_float4x4
            let explode: SIMD3<Float>
            let pivot: SIMD3<Float>
            let axis: SIMD3<Float>
            let motion: GearPartMotion
            let colour: SIMD3<Float>
            let roughness: Float
            let surface: Float
            /// The instrument bed is a one-sided horizontal plane, not a solid enclosure.
            let floorHeight: Float?
        }
        private struct GPUAssembly {
            let parts: [GPUPart]
            let target: SIMD3<Float>
            let distance: Float
            let driverRadius: Float
            let rackRepeat: Float
        }
        private let device = GearMetalResources.device
        private let queue = GearMetalResources.device?.makeCommandQueue()
        private var cache: [String: GPUAssembly] = [:]
        private var recency: [String] = []
        private var assembly: GPUAssembly?
        private var kind: GearKind = .spur
        private var input = GearTransmissionInputs()
        private var phase: Double = 0
        private var tilt: SIMD2<Float> = .zero
        private var orbit: SIMD2<Float> = .zero
        private var exploded: Float = 0
        private var hologram: Float = 0
        private var reducedMotion = false
        private var reducedTransparency = false
        private var colourTarget: MTLTexture?
        private var multisampleTarget: MTLTexture?
        private var depthTarget: MTLTexture?
        private var targetSize = SIMD2<Int>(0, 0)

        func update(kind: GearKind, inputs: GearTransmissionInputs, phase: Double,
                    tilt: SIMD2<Float>, orbit: SIMD2<Float>, exploded: Double,
                    hologram: Bool, reducedMotion: Bool, reducedTransparency: Bool) {
            self.kind = kind
            self.input = GearTransmission.normalizedInputs(kind: kind, inputs: inputs)
            self.phase = phase.isFinite ? phase : 0
            self.tilt = reducedMotion ? .zero : Self.finiteVector(tilt, range: -1...1)
            self.orbit = SIMD2(orbit.x.isFinite ? atan2(sin(orbit.x), cos(orbit.x)) : 0,
                               min(0.75, max(-0.75, orbit.y.isFinite ? orbit.y : 0)))
            self.exploded = Float(min(1, max(0, exploded.isFinite ? exploded : 0)))
            self.hologram = hologram ? 1 : 0
            self.reducedMotion = reducedMotion
            self.reducedTransparency = reducedTransparency
            // Quarter-degree mesh quantisation is below the view's explanatory precision.
            // RPM, torque, phase, camera, optics and separation never rebuild the mesh.
            let helixQuarter = Int((input.helixAngleDegrees * 4).rounded())
            let key = "\(kind.rawValue):\(Int(input.driverTeeth)):\(Int(input.drivenTeeth)):\(helixQuarter):\(Int(input.wormStarts))"
            if let stored = cache[key] {
                assembly = stored
                recency.removeAll { $0 == key }
                recency.append(key)
                return
            }
            guard let device else { return }
            var geometryInput = input
            geometryInput.helixAngleDegrees = Double(helixQuarter) / 4
            let geometry = GearGeometry.assembly(kind: kind, inputs: geometryInput)
            let parts: [GPUPart] = geometry.parts.compactMap { part in
                guard !part.mesh.vertices.isEmpty else { return nil }
                let buffer = part.mesh.vertices.withUnsafeBytes { bytes -> MTLBuffer? in
                    guard let pointer = bytes.baseAddress else { return nil }
                    return device.makeBuffer(bytes: pointer, length: bytes.count, options: .storageModeShared)
                }
                guard let buffer else { return nil }
                buffer.label = "\(kind.title) immutable geometry"
                return GPUPart(buffer: buffer, vertexCount: part.mesh.vertices.count,
                    transform: part.transform, explode: part.explode,
                    pivot: part.rotationPivot, axis: part.rotationAxis, motion: part.motion,
                    colour: part.colour, roughness: part.roughness, surface: part.surface,
                    floorHeight: part.surface == 1 ? (part.transform * part.mesh.vertices[0].position).y : nil)
            }
            let gpu = GPUAssembly(parts: parts, target: geometry.target, distance: geometry.cameraDistance,
                                  driverRadius: geometry.driverRadius, rackRepeat: geometry.rackRepeat)
            assembly = gpu
            cache[key] = gpu
            recency.append(key)
            // Keep only three recent shapes. Count/helix editing cannot grow GPU memory forever.
            while recency.count > 3 { cache.removeValue(forKey: recency.removeFirst()) }
        }

        private static func finiteVector(_ vector: SIMD2<Float>, range: ClosedRange<Float>) -> SIMD2<Float> {
            SIMD2(min(range.upperBound, max(range.lowerBound, vector.x.isFinite ? vector.x : 0)),
                  min(range.upperBound, max(range.lowerBound, vector.y.isFinite ? vector.y : 0)))
        }

        func releaseTargets() {
            colourTarget = nil
            multisampleTarget = nil
            depthTarget = nil
            targetSize = .zero
            assembly = nil
            cache.removeAll()
            recency.removeAll()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { targetSize = .zero }

        private func prepareTargets(width: Int, height: Int) -> Bool {
            guard let device else { return false }
            guard targetSize != SIMD2(width, height) || colourTarget == nil else { return true }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                width: width, height: height, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            colourTarget = device.makeTexture(descriptor: descriptor)
            colourTarget?.label = "Gear scene · refraction source"
            let sampleCount = GearMetalResources.sampleCount
            if sampleCount > 1 {
                descriptor.textureType = .type2DMultisample
                descriptor.sampleCount = sampleCount
                descriptor.usage = .renderTarget
                multisampleTarget = device.makeTexture(descriptor: descriptor)
                multisampleTarget?.label = "Gear scene · antialiasing"
            } else { multisampleTarget = nil }
            descriptor.pixelFormat = .depth32Float
            descriptor.textureType = sampleCount > 1 ? .type2DMultisample : .type2D
            descriptor.sampleCount = sampleCount
            descriptor.usage = .renderTarget
            depthTarget = device.makeTexture(descriptor: descriptor)
            depthTarget?.label = "Gear geometry · depth"
            targetSize = SIMD2(width, height)
            return colourTarget != nil && depthTarget != nil && (sampleCount == 1 || multisampleTarget != nil)
        }

        func draw(in view: MTKView) {
            guard let scene = GearMetalResources.scene, let optics = GearMetalResources.optics,
                  let depth = GearMetalResources.depth, let assembly,
                  let drawable = view.currentDrawable,
                  let screenPass = view.currentRenderPassDescriptor,
                  let command = queue?.makeCommandBuffer() else { return }
            let width = drawable.texture.width, height = drawable.texture.height
            guard prepareTargets(width: width, height: height), let colourTarget, let depthTarget else { return }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = multisampleTarget ?? colourTarget
            pass.colorAttachments[0].resolveTexture = multisampleTarget == nil ? nil : colourTarget
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = multisampleTarget == nil ? .store : .multisampleResolve
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.006, green: 0.010, blue: 0.020, alpha: 1)
            pass.depthAttachment.texture = depthTarget
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.storeAction = .dontCare
            pass.depthAttachment.clearDepth = 1
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
            encoder.label = "Chrome shafts and teeth"
            encoder.setRenderPipelineState(scene)
            encoder.setDepthStencilState(depth)
            encoder.setCullMode(.none)
            let aspect = Float(width) / Float(max(1, height))
            let yaw = Float(0.36) + orbit.x + tilt.x * 0.16
            let pitch = min(1.15, max(-0.42, 0.28 + orbit.y + tilt.y * 0.11))
            let target = assembly.target + SIMD3<Float>(0, 0.03 * exploded, 0.25 * exploded)
            let distance = assembly.distance * 0.83 + exploded * 1.30
            let eye = target + SIMD3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
            let projection = GearMatrix.perspective(fov: 36 * .pi / 180, aspect: aspect, near: 0.1, far: 40)
            let viewProjection = projection * GearMatrix.lookAt(eye: eye, target: target)
            let ratio = kind == .worm ? input.drivenTeeth / input.wormStarts : input.drivenTeeth / input.driverTeeth
            // Derive output in Double before wrapping each axis independently. Slow reductions
            // continue to advance even when the input has passed many complete revolutions.
            let inputAngle = Float(phase.truncatingRemainder(dividingBy: 2 * .pi))
            var driverBase: Double = 0
            if kind == .rackAndPinion {
                let pitch = 2 * Double.pi * Double(assembly.driverRadius) / input.driverTeeth
                let rackCells = Int((7 / pitch).rounded(.up))
                // At x=0 an even-cell rack has a root, an odd-cell rack a tooth crest.
                // Align the bottom pinion tooth/root complementarily; travel still uses
                // the unshifted phase, so repeating the rack never changes its kinematics.
                driverBase = -.pi / 2 - (rackCells.isMultiple(of: 2) ? 0 : .pi / input.driverTeeth)
            }
            let driverAngle = Float((phase + driverBase).truncatingRemainder(dividingBy: 2 * .pi))
            let outputBase: Double
            if kind == .internalGear {
                outputBase = .pi / input.drivenTeeth
            } else if kind == .screw {
                // The driver touches at +Y (theta=pi/2), the output at -Y (-pi/2).
                // Nout*(thetaOut-phiOut) = pi - Nin*(thetaIn-phiIn) modulo 2pi:
                // phiOut0 = thetaOut + (Nin/Nout)*thetaIn + pi/Nout.
                outputBase = -.pi / 2 + input.driverTeeth / input.drivenTeeth * .pi / 2 + .pi / input.drivenTeeth
            } else {
                outputBase = .pi + .pi / input.drivenTeeth
            }
            let outputPhase = outputBase + phase / ratio * (kind == .internalGear ? 1 : -1)
            let outputAngle = Float(outputPhase.truncatingRemainder(dividingBy: 2 * .pi))
            for part in assembly.parts {
                // Preserve underside inspection without drawing the bed's opaque back face
                // between the camera and every gear when an orbit crosses below its plane.
                if let floorHeight = part.floorHeight,
                   eye.y <= floorHeight + part.explode.y * exploded + 0.0001 { continue }
                // Positive local shaft arrows are a deliberate inspection affordance.
                if part.surface > 1.5 && hologram < 0.5 && exploded < 0.05 { continue }
                var model = GearMatrix.translation(part.explode * exploded) * part.transform
                switch part.motion {
                case .fixed: break
                case .driver, .driven:
                    let angle = part.motion == .driver ? driverAngle : outputAngle
                    model = GearMatrix.translation(part.explode * exploded)
                        * GearMatrix.translation(part.pivot)
                        * GearMatrix.rotation(angle, axis: part.axis)
                        * GearMatrix.translation(-part.pivot) * part.transform
                case .rack:
                    let travel = phase * Double(assembly.driverRadius)
                    let period = Double(max(0.001, assembly.rackRepeat))
                    let repeatPosition = travel - ((travel + period / 2) / period).rounded(.down) * period
                    model = GearMatrix.translation(SIMD3(Float(repeatPosition), 0, 0) + part.explode * exploded) * part.transform
                }
                var uniforms = GearSceneUniforms(viewProjection: viewProjection, model: model,
                    cameraAndTime: SIMD4(eye, reducedMotion ? 0 : inputAngle),
                    tiltAndAspect: SIMD4(tilt.x, tilt.y, aspect, exploded),
                    material: SIMD4(part.colour, part.roughness),
                    features: SIMD4(1, hologram, part.surface, 0))
                encoder.setVertexBuffer(part.buffer, offset: 0, index: 0)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<GearSceneUniforms>.stride, index: 1)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GearSceneUniforms>.stride, index: 1)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: part.vertexCount)
            }
            encoder.endEncoding()
            guard let final = command.makeRenderCommandEncoder(descriptor: screenPass) else { return }
            final.label = "Sampled optical cover"
            final.setRenderPipelineState(optics)
            final.setFragmentTexture(colourTarget, index: 0)
            var uniforms = GearOpticsUniforms(optics: SIMD4(tilt.x, tilt.y, inputAngle, aspect),
                settings: SIMD4(hologram, reducedMotion ? 1 : 0, reducedTransparency ? 1 : 0, exploded),
                viewport: SIMD4(Float(width), Float(height), 0, 0))
            final.setFragmentBytes(&uniforms, length: MemoryLayout<GearOpticsUniforms>.stride, index: 0)
            final.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            final.endEncoding()
            command.present(drawable)
            command.commit()
        }
    }
}
