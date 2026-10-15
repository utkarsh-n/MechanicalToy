import Foundation
import simd
import MechanicalCore

/// Schematic tooth surfaces: real 3D topology, deliberately not a manufacturable tooth design.
/// Four-component fields keep the CPU layout identical to the Metal vertex layout.
struct GearVertex {
    var position: SIMD4<Float>
    var normal: SIMD4<Float>
    var detail: SIMD4<Float>
}

struct GearMesh {
    var vertices: [GearVertex]
}

enum GearPartMotion {
    case fixed, driver, driven, rack
}

struct GearGeometryPart {
    var mesh: GearMesh
    var transform: simd_float4x4 = matrix_identity_float4x4
    var explode: SIMD3<Float> = .zero
    var rotationPivot: SIMD3<Float> = .zero
    var rotationAxis: SIMD3<Float> = SIMD3(0, 0, 1)
    var motion: GearPartMotion = .fixed
    var colour: SIMD3<Float> = SIMD3(0.79, 0.83, 0.90)
    var roughness: Float = 0.18
    /// 0: machined metal; 1: instrument floor; 2: emissive shaft/measurement lines.
    var surface: Float = 0
}

struct GearAssemblyGeometry {
    var parts: [GearGeometryPart]
    var target: SIMD3<Float>
    var cameraDistance: Float
    var driverRadius: Float
    var rackRepeat: Float
}

struct GearMeshBuilder {
    private(set) var vertices: [GearVertex] = []

    mutating func triangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>,
                           normals: [SIMD3<Float>]? = nil, detail: Float = 0) {
        let crossed = simd_cross(b - a, c - a)
        guard simd_length_squared(crossed) > 0.0000000001 else { return }
        let face = simd_normalize(crossed)
        for (index, point) in [a, b, c].enumerated() {
            let normal = normals?[index] ?? face
            vertices.append(GearVertex(position: SIMD4(point, 1), normal: SIMD4(normal, 0),
                                       detail: SIMD4(detail, 0, 0, 0)))
        }
    }

    mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
                       normals: [SIMD3<Float>]? = nil, detail: Float = 0) {
        triangle(a, b, c, normals: normals.map { [$0[0], $0[1], $0[2]] }, detail: detail)
        triangle(a, c, d, normals: normals.map { [$0[0], $0[2], $0[3]] }, detail: detail)
    }

    var mesh: GearMesh { GearMesh(vertices: vertices) }

    /// Extruded, optionally twisted/frustum-shaped tooth profile with an actual open bore.
    static func gear(teeth: Int, radius: Float, width: Float, bore: Float,
                     twist: Float = 0, twistOffset: Float = 0,
                     radiusBack: Float? = nil, zOffset: Float = 0,
                     curved: Bool = false) -> GearMesh {
        var result = GearMeshBuilder()
        let sections = (abs(twist) > 0.001 || curved) ? 14 : 2
        let segments = teeth * 10
        let bevel = min(width * 0.12, radius / Float(teeth) * 0.38)
        let module = 2 * radius / Float(teeth)
        let back = radiusBack ?? radius
        let weights: [Float] = [1, 1, 0.65, -0.8, -0.9, -0.9, -0.9, -0.8, 0.65, 1]
        var zs: [Float] = [-width / 2, -width / 2 + bevel]
        for index in 1..<sections { zs.append(-width / 2 + bevel + (width - 2 * bevel) * Float(index) / Float(sections)) }
        zs += [width / 2 - bevel, width / 2]
        func point(_ index: Int, _ z: Float) -> SIMD3<Float> {
            let t = (z + width / 2) / width
            let pitch = back + (radius - back) * t
            let axialBevel = min(abs(z + width / 2), abs(z - width / 2)) < bevel * 0.4 ? bevel : 0
            let toothDepth = module * (pitch / radius)
            let r = max(bore + min(0.04, radius * 0.08), pitch + weights[index % 10] * toothDepth - axialBevel)
            let angularTwist = curved ? twist * (t * t - 0.25) : twist * z
            let angle = Float(index) * 2 * .pi / Float(segments) + angularTwist + twistOffset
            return SIMD3(r * cos(angle), r * sin(angle), z + zOffset)
        }
        for row in 0..<(zs.count - 1) {
            for index in 0..<segments {
                result.quad(point(index, zs[row]), point(index + 1, zs[row]),
                            point(index + 1, zs[row + 1]), point(index, zs[row + 1]), detail: 0.5)
            }
        }
        for (z, front) in [(zs.first!, false), (zs.last!, true)] {
            for index in 0..<segments {
                let outerA = point(index, z), outerB = point(index + 1, z)
                let thetaA = atan2(outerA.y, outerA.x), thetaB = atan2(outerB.y, outerB.x)
                let innerA = SIMD3(bore * cos(thetaA), bore * sin(thetaA), z + zOffset)
                let innerB = SIMD3(bore * cos(thetaB), bore * sin(thetaB), z + zOffset)
                if front { result.quad(innerA, outerA, outerB, innerB, detail: 1) }
                else { result.quad(innerB, outerB, outerA, innerA, detail: 1) }
            }
        }
        // The bore is independent of the tooth twist, and remains open through both faces.
        let boreSegments = max(48, teeth * 2)
        for index in 0..<boreSegments {
            let a = Float(index) * 2 * .pi / Float(boreSegments)
            let b = Float(index + 1) * 2 * .pi / Float(boreSegments)
            let lowA = SIMD3(bore * cos(a), bore * sin(a), -width / 2 + zOffset)
            let lowB = SIMD3(bore * cos(b), bore * sin(b), -width / 2 + zOffset)
            let highA = SIMD3(bore * cos(a), bore * sin(a), width / 2 + zOffset)
            let highB = SIMD3(bore * cos(b), bore * sin(b), width / 2 + zOffset)
            result.quad(lowA, highA, highB, lowB,
                        normals: [SIMD3(-cos(a), -sin(a), 0), SIMD3(-cos(a), -sin(a), 0),
                                  SIMD3(-cos(b), -sin(b), 0), SIMD3(-cos(b), -sin(b), 0)])
        }
        return result.mesh
    }

    static func ring(teeth: Int, radius: Float, outer: Float, width: Float) -> GearMesh {
        var result = GearMeshBuilder()
        let count = teeth * 10
        let module = 2 * radius / Float(teeth)
        let weights: [Float] = [1, 1, 0.65, -0.8, -0.9, -0.9, -0.9, -0.8, 0.65, 1]
        func inner(_ i: Int, _ z: Float) -> SIMD3<Float> {
            let a = Float(i) * 2 * .pi / Float(count)
            let r = radius - weights[i % 10] * module
            return SIMD3(r * cos(a), r * sin(a), z)
        }
        func outside(_ i: Int, _ z: Float) -> SIMD3<Float> {
            let a = Float(i) * 2 * .pi / Float(count)
            return SIMD3(outer * cos(a), outer * sin(a), z)
        }
        let low = -width / 2, high = width / 2
        for i in 0..<count {
            result.quad(inner(i, low), inner(i, high), inner(i + 1, high), inner(i + 1, low), detail: 0.5)
            result.quad(outside(i, low), outside(i + 1, low), outside(i + 1, high), outside(i, high))
            result.quad(inner(i, high), outside(i, high), outside(i + 1, high), inner(i + 1, high), detail: 1)
            result.quad(inner(i + 1, low), outside(i + 1, low), outside(i, low), inner(i, low), detail: 1)
        }
        return result.mesh
    }

    static func cylinder(radius: Float, length: Float, bore: Float = 0, segments: Int = 64) -> GearMesh {
        var result = GearMeshBuilder()
        let low = -length / 2, high = length / 2
        for i in 0..<segments {
            let a = Float(i) * 2 * .pi / Float(segments), b = Float(i + 1) * 2 * .pi / Float(segments)
            let nA = SIMD3(cos(a), sin(a), 0), nB = SIMD3(cos(b), sin(b), 0)
            let a0 = nA * radius + SIMD3(0, 0, low), a1 = nA * radius + SIMD3(0, 0, high)
            let b0 = nB * radius + SIMD3(0, 0, low), b1 = nB * radius + SIMD3(0, 0, high)
            result.quad(a0, b0, b1, a1, normals: [nA, nB, nB, nA])
            if bore > 0 {
                let innerA0 = nA * bore + SIMD3(0, 0, low), innerA1 = nA * bore + SIMD3(0, 0, high)
                let innerB0 = nB * bore + SIMD3(0, 0, low), innerB1 = nB * bore + SIMD3(0, 0, high)
                result.quad(innerA0, innerA1, innerB1, innerB0, normals: [-nA, -nA, -nB, -nB])
                result.quad(innerA1, a1, b1, innerB1, detail: 1)
                result.quad(innerB0, b0, a0, innerA0, detail: 1)
            } else {
                result.triangle(SIMD3(0, 0, high), a1, b1, detail: 1)
                result.triangle(SIMD3(0, 0, low), b0, a0, detail: 1)
            }
        }
        return result.mesh
    }

    static func cone(radius: Float, length: Float, segments: Int = 20) -> GearMesh {
        var result = GearMeshBuilder()
        let tip = SIMD3<Float>(0, 0, length / 2)
        let centre = SIMD3<Float>(0, 0, -length / 2)
        for i in 0..<segments {
            let a = Float(i) * 2 * .pi / Float(segments)
            let b = Float(i + 1) * 2 * .pi / Float(segments)
            let first = SIMD3<Float>(radius * cos(a), radius * sin(a), -length / 2)
            let second = SIMD3<Float>(radius * cos(b), radius * sin(b), -length / 2)
            result.triangle(first, second, tip)
            result.triangle(centre, second, first)
        }
        return result.mesh
    }

    static func thread(length: Float, starts: Int) -> GearMesh {
        var result = GearMeshBuilder()
        let circumferential = 96, rows = 180
        let lead = Float(starts) * 0.30
        func point(_ i: Int, _ j: Int) -> SIMD3<Float> {
            let angle = Float(i) * 2 * .pi / Float(circumferential)
            let z = (Float(j) / Float(rows) - 0.5) * length
            let wave = Float(starts) * (angle - 2 * .pi * z / lead)
            let unit = wave / (2 * .pi) - (wave / (2 * .pi)).rounded(.down)
            // Broad roots, sloped flanks, and a narrow crest make a visibly machined screw.
            let tooth = max(0, min(1, (0.30 - abs(unit - 0.5)) / 0.19))
            let endFade = min(1, max(0, (length / 2 - abs(z)) / 0.10))
            let radius = 0.17 + tooth * endFade * 0.125
            return SIMD3(radius * cos(angle), radius * sin(angle), z)
        }
        for row in 0..<rows {
            for i in 0..<circumferential {
                result.quad(point(i, row), point(i + 1, row), point(i + 1, row + 1), point(i, row + 1))
            }
        }
        return result.mesh
    }

    static func rack(pinionRadius: Float, teeth: Int, length: Float) -> GearMesh {
        var result = GearMeshBuilder()
        let pitch = 2 * .pi * pinionRadius / Float(teeth)
        let toothHeight = 2 * pinionRadius / Float(teeth)
        let count = Int(ceil(length / pitch))
        let actualLength = Float(count) * pitch
        let halfWidth: Float = 0.22
        let base: Float = -0.28
        var outline: [SIMD2<Float>] = [SIMD2(-actualLength / 2, base), SIMD2(actualLength / 2, base)]
        let shape: [(Float, Float)] = [(0, -0.8), (0.2, -0.8), (0.35, 1), (0.65, 1), (0.8, -0.8), (1, -0.8)]
        for tooth in (0..<count).reversed() {
            for (unit, height) in shape.reversed() {
                outline.append(SIMD2(-actualLength / 2 + (Float(tooth) + unit) * pitch, height * toothHeight))
            }
        }
        // The 2D side polygon is extruded along the visible shaft axis.
        for i in outline.indices {
            let next = (i + 1) % outline.count
            let a = outline[i], b = outline[next]
            result.quad(SIMD3(a.x, a.y, -halfWidth), SIMD3(b.x, b.y, -halfWidth),
                        SIMD3(b.x, b.y, halfWidth), SIMD3(a.x, a.y, halfWidth))
        }
        // Split the face into tooth cells rather than fan-triangulating a concave polygon.
        for tooth in 0..<count {
            let start = -actualLength / 2 + Float(tooth) * pitch
            for index in 0..<(shape.count - 1) {
                let a = SIMD2(start + shape[index].0 * pitch, shape[index].1 * toothHeight)
                let b = SIMD2(start + shape[index + 1].0 * pitch, shape[index + 1].1 * toothHeight)
                result.quad(SIMD3(a.x, base, halfWidth), SIMD3(b.x, base, halfWidth),
                            SIMD3(b.x, b.y, halfWidth), SIMD3(a.x, a.y, halfWidth), detail: 1)
                result.quad(SIMD3(a.x, a.y, -halfWidth), SIMD3(b.x, b.y, -halfWidth),
                            SIMD3(b.x, base, -halfWidth), SIMD3(a.x, base, -halfWidth), detail: 1)
            }
        }
        return result.mesh
    }

    static func floor(y: Float) -> GearMesh {
        var result = GearMeshBuilder()
        result.quad(SIMD3(-6, y, -6), SIMD3(-6, y, 6), SIMD3(6, y, 6), SIMD3(6, y, -6))
        return result.mesh
    }
}

enum GearGeometry {
    static func assembly(kind: GearKind, inputs: GearTransmissionInputs) -> GearAssemblyGeometry {
        let input = GearTransmission.normalizedInputs(kind: kind, inputs: inputs)
        let driverCount = Int(input.driverTeeth), drivenCount = Int(input.drivenTeeth)
        let maximum = Float(max(driverCount, drivenCount))
        let r1 = Float(driverCount) / maximum * 1.04, r2 = Float(drivenCount) / maximum * 1.04
        let helix = Float(input.helixAngleDegrees) * .pi / 180
        let silver = SIMD3<Float>(0.78, 0.83, 0.91), gunmetal = SIMD3<Float>(0.42, 0.52, 0.63)
        var parts: [GearGeometryPart] = []
        var target = SIMD3<Float>(0, -0.02, 0)
        var distance: Float = 6.2
        var floorY: Float = -1.22
        var rackRepeat: Float = 0
        func body(_ mesh: GearMesh, centre: SIMD3<Float>, orientation: simd_float4x4 = matrix_identity_float4x4,
                  movement: GearPartMotion, explode: SIMD3<Float>, dark: Bool = false) -> GearGeometryPart {
            GearGeometryPart(mesh: mesh, transform: GearMatrix.translation(centre) * orientation,
                             explode: explode, rotationPivot: centre, rotationAxis: orientation.columns.2.xyz,
                             motion: movement, colour: dark ? gunmetal : silver)
        }
        func addShaft(centre: SIMD3<Float>, radius: Float, axis: simd_float4x4 = matrix_identity_float4x4,
                      movement: GearPartMotion, explode: SIMD3<Float>, length: Float = 1.8) {
            parts.append(body(GearMeshBuilder.cylinder(radius: radius, length: length), centre: centre,
                              orientation: axis, movement: movement, explode: explode, dark: true))
            // A pale bearing collar gives the shaft a clear depth/rotation cue.
            parts.append(body(GearMeshBuilder.cylinder(radius: radius * 1.30, length: 0.055, bore: radius * 0.85),
                              centre: centre + (axis * SIMD4<Float>(0, 0, -0.49, 0)).xyz,
                              orientation: axis, movement: .fixed, explode: explode))
            parts.append(GearGeometryPart(mesh: GearMeshBuilder.cylinder(radius: 0.009, length: length + 1.0, segments: 12),
                transform: GearMatrix.translation(centre) * axis, explode: SIMD3(explode.x, explode.y, 0),
                colour: SIMD3(0.20, 0.83, 0.96), roughness: 0.3, surface: 2))
            let tipCentre = centre + (axis * SIMD4<Float>(0, 0, (length + 1.0) / 2 + 0.065, 0)).xyz
            parts.append(GearGeometryPart(mesh: GearMeshBuilder.cone(radius: 0.040, length: 0.13),
                transform: GearMatrix.translation(tipCentre) * axis,
                explode: SIMD3(explode.x, explode.y, 0), colour: SIMD3(0.20, 0.83, 0.96), surface: 2))
        }
        func addFasteners(centre: SIMD3<Float>, radius: Float, width: Float,
                          axis: simd_float4x4 = matrix_identity_float4x4,
                          movement: GearPartMotion, explode: SIMD3<Float>) {
            // Four dark counterbores and bright screw heads interrupt the face realistically.
            let screwRadius = max(0.018, min(0.046, radius * 0.06))
            let ring = radius * 0.56
            for index in 0..<4 {
                let a = Float(index) * .pi / 2 + .pi / 4
                let local = SIMD4<Float>(ring * cos(a), ring * sin(a), width / 2 + 0.008, 1)
                let offset = (axis * local).xyz
                parts.append(body(GearMeshBuilder.cylinder(radius: screwRadius * 1.40, length: 0.012),
                                  centre: centre + offset, orientation: axis, movement: movement,
                                  explode: explode, dark: true))
                parts[parts.count - 1].rotationPivot = centre
                parts.append(body(GearMeshBuilder.cylinder(radius: screwRadius, length: 0.018, segments: 6),
                                  centre: centre + offset + (axis * SIMD4<Float>(0, 0, 0.012, 0)).xyz,
                                  orientation: axis, movement: movement, explode: explode))
                parts[parts.count - 1].rotationPivot = centre
            }
        }
        switch kind {
        case .spur, .helical, .doubleHelical, .herringbone:
            let centres = [SIMD3<Float>(-r2, 0, 0), SIMD3<Float>(r1, 0, 0)]
            let radii = [r1, r2], counts = [driverCount, drivenCount]
            let width: Float = kind == .spur ? 0.34 : 0.62
            for i in 0..<2 {
                let motion: GearPartMotion = i == 0 ? .driver : .driven
                let spread: Float = i == 0 ? -0.28 : 0.28
                let explode = SIMD3<Float>(spread, 0, i == 0 ? 0.72 : 1.12)
                let hand: Float = i == 0 ? 1 : -1
                let slope = tan(helix) / radii[i] * hand
                if kind == .doubleHelical || kind == .herringbone {
                    let gap: Float = kind == .doubleHelical ? 0.075 : 0
                    let half = (width - gap) / 2
                    for sign: Float in [-1, 1] {
                        let z = sign * (gap / 2 + half / 2)
                        let twist = -sign * slope
                        let mesh = GearMeshBuilder.gear(teeth: counts[i], radius: radii[i], width: half,
                            bore: radii[i] * 0.24, twist: twist, twistOffset: -slope * half / 2, zOffset: z)
                        parts.append(body(mesh, centre: centres[i], movement: motion, explode: explode, dark: i == 1))
                    }
                } else {
                    parts.append(body(GearMeshBuilder.gear(teeth: counts[i], radius: radii[i], width: width,
                        bore: radii[i] * 0.24, twist: kind == .helical ? slope : 0),
                        centre: centres[i], movement: motion, explode: explode, dark: i == 1))
                }
                addFasteners(centre: centres[i], radius: radii[i], width: width, movement: motion, explode: explode)
                addShaft(centre: centres[i], radius: radii[i] * 0.16, movement: motion,
                         explode: SIMD3(spread, 0, -0.45))
            }
            distance = 5.75 + (r1 + r2) * 0.3
        case .internalGear:
            let ringRadius: Float = 1.12, pinionRadius = Float(driverCount) / Float(drivenCount) * ringRadius
            parts.append(body(GearMeshBuilder.ring(teeth: drivenCount, radius: ringRadius, outer: 1.34, width: 0.39),
                              centre: .zero, movement: .driven, explode: SIMD3(-0.2, 0, 0.75)))
            let centre = SIMD3<Float>(ringRadius - pinionRadius, 0, 0)
            parts.append(body(GearMeshBuilder.gear(teeth: driverCount, radius: pinionRadius, width: 0.35,
                                                  bore: pinionRadius * 0.25),
                              centre: centre, movement: .driver, explode: SIMD3(0.25, 0, 1.10), dark: true))
            addShaft(centre: centre, radius: pinionRadius * 0.17, movement: .driver, explode: SIMD3(0.25, 0, -0.4))
            addFasteners(centre: centre, radius: pinionRadius, width: 0.35, movement: .driver, explode: SIMD3(0.25, 0, 1.1))
            floorY = -1.45
            distance = 5.8
        case .worm:
            let wheelCentre = SIMD3<Float>(0, -0.32, 0)
            parts.append(body(GearMeshBuilder.gear(teeth: drivenCount, radius: 1.02, width: 0.42, bore: 0.25,
                                                  twist: -0.15),
                              centre: wheelCentre, movement: .driven, explode: SIMD3(0, -0.20, 0.85)))
            addFasteners(centre: wheelCentre, radius: 1.02, width: 0.42, movement: .driven, explode: SIMD3(0, -0.20, 0.85))
            addShaft(centre: wheelCentre, radius: 0.17, movement: .driven, explode: SIMD3(0, -0.2, -0.4))
            let wormCentre = SIMD3<Float>(0, 0.88, 0.02)
            let axis = GearMatrix.rotation(.pi / 2, axis: SIMD3(0, 1, 0))
            parts.append(body(GearMeshBuilder.thread(length: 2.6, starts: Int(input.wormStarts)), centre: wormCentre,
                              orientation: axis, movement: .driver, explode: SIMD3(0, 0.30, 0.10)))
            addShaft(centre: wormCentre, radius: 0.13, axis: axis, movement: .driver,
                     explode: SIMD3(0, 0.3, -0.1), length: 3.35)
            target.y = 0.04
            floorY = -1.45
            distance = 6.3
        case .screw:
            let radii: [Float] = [max(0.25, r1), r2]
            let centres = [SIMD3<Float>(0, -radii[1], 0), SIMD3<Float>(0, radii[0], 0)]
            let axes = [matrix_identity_float4x4, GearMatrix.rotation(-2 * helix, axis: SIMD3(0, 1, 0))]
            let counts = [driverCount, drivenCount]
            for i in 0..<2 {
                let motion: GearPartMotion = i == 0 ? .driver : .driven
                let explode = SIMD3<Float>(0, i == 0 ? -0.32 : 0.32, i == 0 ? 0.60 : 0.05)
                parts.append(body(GearMeshBuilder.gear(teeth: counts[i], radius: radii[i], width: 1.0,
                    bore: 0.18, twist: tan(helix) / radii[i]), centre: centres[i],
                    orientation: axes[i], movement: motion, explode: explode, dark: i == 1))
                addShaft(centre: centres[i], radius: 0.125, axis: axes[i], movement: motion,
                         explode: SIMD3(0, explode.y, -0.30), length: 2.0)
            }
            floorY = -radii[0] - radii[1] - 0.18
            distance = 6.6
        case .rackAndPinion:
            let radius: Float = 0.82, centre = SIMD3<Float>(0, 0.39, 0)
            parts.append(body(GearMeshBuilder.gear(teeth: driverCount, radius: radius, width: 0.39, bore: 0.20),
                              centre: centre, movement: .driver, explode: SIMD3(0, 0.20, 0.8)))
            addShaft(centre: centre, radius: 0.14, movement: .driver, explode: SIMD3(0, 0.20, -0.35))
            addFasteners(centre: centre, radius: radius, width: 0.39, movement: .driver, explode: SIMD3(0, 0.20, 0.8))
            let pitch = 2 * .pi * radius / Float(driverCount)
            rackRepeat = Float(max(8, Int(2.8 / pitch))) * pitch
            parts.append(body(GearMeshBuilder.rack(pinionRadius: radius, teeth: driverCount, length: 7),
                              centre: SIMD3(0, 0.39 - radius, 0), movement: .rack,
                              explode: SIMD3(0, -0.24, 0.1), dark: true))
            floorY = -0.9
            target.y = 0.0
            distance = 6.0
        case .bevel, .spiralBevel, .mitre, .hypoid:
            let spiral = kind == .spiralBevel || kind == .hypoid
            let axis = GearMatrix.rotation(.pi / 2, axis: SIMD3(0, 1, 0))
            let radiusA = max(0.35, r1), radiusB = r2
            let widthA = radiusB * 0.42, widthB = radiusA * 0.42
            let centreA = SIMD3<Float>(0, kind == .hypoid ? -0.26 : 0, radiusB * 0.79)
            let centreB = SIMD3<Float>(radiusA * 0.79, kind == .hypoid ? 0.09 : 0, 0)
            let boreA = radiusA * 0.20, boreB = radiusB * (kind == .hypoid ? 0.57 : 0.23)
            parts.append(body(GearMeshBuilder.gear(teeth: driverCount, radius: radiusA, width: widthA, bore: boreA,
                twist: spiral ? 0.46 : 0, radiusBack: radiusA * 0.58, curved: spiral), centre: centreA,
                movement: .driver, explode: SIMD3(-0.20, kind == .hypoid ? -0.13 : 0, 0.75)))
            parts.append(body(GearMeshBuilder.gear(teeth: drivenCount, radius: radiusB, width: widthB, bore: boreB,
                twist: spiral ? -0.46 : 0, radiusBack: radiusB * 0.58, curved: spiral), centre: centreB,
                orientation: axis, movement: .driven, explode: SIMD3(0.75, kind == .hypoid ? 0.13 : 0, -0.20), dark: true))
            addShaft(centre: centreA, radius: boreA * 0.70, movement: .driver,
                     explode: SIMD3(-0.20, 0, -0.35), length: 1.45)
            if kind == .hypoid {
                // Preserve the open final-drive ring instead of filling it with a solid hub.
                parts.append(body(GearMeshBuilder.cylinder(radius: boreB * 1.18, length: 0.12, bore: boreB * 0.95),
                    centre: centreB - SIMD3(0.30, 0, 0), orientation: axis, movement: .driven,
                    explode: SIMD3(0.75, 0.13, -0.20), dark: true))
                parts.append(GearGeometryPart(mesh: GearMeshBuilder.cylinder(radius: 0.009, length: 2.5, segments: 12),
                    transform: GearMatrix.translation(centreB) * axis, colour: SIMD3(0.2, 0.83, 0.96), surface: 2))
                parts.append(GearGeometryPart(mesh: GearMeshBuilder.cone(radius: 0.04, length: 0.13),
                    transform: GearMatrix.translation(centreB + SIMD3(1.315, 0, 0)) * axis,
                    colour: SIMD3(0.2, 0.83, 0.96), surface: 2))
            } else {
                addShaft(centre: centreB, radius: boreB * 0.7, axis: axis, movement: .driven,
                         explode: SIMD3(-0.35, 0, -0.20), length: 1.45)
            }
            target = SIMD3(radiusA * 0.34, -0.05, radiusB * 0.34)
            floorY = -radiusB - 0.20
            distance = 5.65
        }
        // A low-contrast instrument bed anchors the machine without masking tooth contours.
        parts.insert(GearGeometryPart(mesh: GearMeshBuilder.floor(y: floorY), colour: SIMD3(0.023, 0.035, 0.060),
                                      roughness: 0.72, surface: 1), at: 0)
        return GearAssemblyGeometry(parts: parts, target: target, cameraDistance: distance,
                                    driverRadius: kind == .rackAndPinion ? 0.82 : r1, rackRepeat: rackRepeat)
    }
}

enum GearMatrix {
    static func translation(_ p: SIMD3<Float>) -> simd_float4x4 {
        var result = matrix_identity_float4x4
        result.columns.3 = SIMD4(p, 1)
        return result
    }

    static func rotation(_ angle: Float, axis: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(simd_quatf(angle: angle, axis: simd_normalize(axis)))
    }

    static func perspective(fov: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let y = 1 / tan(fov / 2), x = y / aspect, z = far / (near - far)
        return simd_float4x4(SIMD4(x, 0, 0, 0), SIMD4(0, y, 0, 0),
                            SIMD4(0, 0, z, -1), SIMD4(0, 0, z * near, 0))
    }

    static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>) -> simd_float4x4 {
        let backward = simd_normalize(eye - target)
        let right = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), backward))
        let up = simd_cross(backward, right)
        return simd_float4x4(SIMD4(right.x, up.x, backward.x, 0),
                            SIMD4(right.y, up.y, backward.y, 0),
                            SIMD4(right.z, up.z, backward.z, 0),
                            SIMD4(-simd_dot(right, eye), -simd_dot(up, eye), -simd_dot(backward, eye), 1))
    }
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
