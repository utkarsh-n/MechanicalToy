import Foundation

public enum RoomBody: String, CaseIterable, Codable, Sendable {
    case wing, car, block, circle
    public var title: String { rawValue.capitalized }
    public var symbol: String {
        switch self { case .wing: "airplane"; case .car: "car.side"; case .block: "square"; case .circle: "circle" }
    }
}

public struct RoomFlowInputs: Sendable {
    public var speed: Double = 5
    public var angle: Double = 8
    public var body: RoomBody = .wing
    public var bodyX: Double = 0.47
    public var bodyY: Double = 0.50
    public init() {}
}

public struct RoomFlowFrame: Sendable {
    public let width: Int
    public let height: Int
    /// RGBA cells contain x velocity, y velocity, dye, and solid occupancy.
    public let pixels: [Float]
    public let peakSpeed: Double
    public let meanSpeed: Double
    public let divergence: Double
    public let time: Double
}

/// Staggered-grid semi-Lagrangian fluid advection with a pressure projection.
/// Artificial viscosity and coarse cells make this an illustrative 2D wind tunnel.
public struct RoomAirflow: Sendable {
    public let width: Int
    public let height: Int
    public let domainWidth: Double = 12
    public let domainHeight: Double = 8
    public let viscosity: Double = 0.035
    public private(set) var time: Double = 0
    private(set) var projectionDivergenceBefore: Double = 0
    private(set) var projectionDivergenceAfter: Double = 0
    private var accumulatedSeconds: Double = 0
    private var u: [Float]
    private var v: [Float]
    private var pressure: [Float]
    private var dye: [Float]
    private var solid: [Bool]
    private var lastBody: RoomBody = .wing
    private var lastX: Double = -1
    private var lastY: Double = -1
    private var lastAngle: Double = -1000

    public init(width: Int = 60, height: Int = 40) {
        self.width = min(160, max(16, width))
        self.height = min(110, max(12, height))
        let cells = self.width * self.height
        u = .init(repeating: 0, count: (self.width + 1) * self.height)
        v = .init(repeating: 0, count: self.width * (self.height + 1))
        pressure = .init(repeating: 0, count: cells)
        dye = .init(repeating: 0, count: cells)
        solid = .init(repeating: false, count: cells)
    }

    public mutating func reset(inputs: RoomFlowInputs) {
        time = 0
        accumulatedSeconds = 0
        pressure = .init(repeating: 0, count: width * height)
        dye = .init(repeating: 0, count: width * height)
        lastX = -1
        rebuildBody(inputs)
        let speed = Float(bound(inputs.speed, 0...14))
        u = .init(repeating: speed, count: (width + 1) * height)
        v = .init(repeating: 0, count: width * (height + 1))
        boundaries(speed)
        project(iterations: 80)
    }

    public mutating func step(seconds: Double, inputs: RoomFlowInputs) {
        guard seconds.isFinite, seconds > 0 else { return }
        rebuildBody(inputs)
        let speed = Float(bound(inputs.speed, 0...14))
        accumulatedSeconds += min(seconds, 0.15)
        let dt = 1.0 / 30
        while accumulatedSeconds + 0.0000001 >= dt {
            guard !Task.isCancelled else { return }
            boundaries(speed)
            advectVelocity(dt: Float(dt))
            boundaries(speed)
            diffuseVelocity(dt: Float(dt))
            boundaries(speed)
            project(iterations: 44)
            boundaries(speed)
            advectDye(dt: Float(dt))
            time += dt
            accumulatedSeconds = max(0, accumulatedSeconds - dt)
        }
    }

    public func frame() -> RoomFlowFrame {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        var peak: Float = 0
        var sum: Double = 0
        var residual: Double = 0
        var count = 0
        let dx = Float(domainWidth) / Float(width)
        let dy = Float(domainHeight) / Float(height)
        for y in 0..<height {
            for x in 0..<width {
                let cell = x + y * width
                let vx = (u[x + y * (width + 1)] + u[x + 1 + y * (width + 1)]) * 0.5
                let vy = (v[x + y * width] + v[x + (y + 1) * width]) * 0.5
                pixels[cell * 4] = vx
                pixels[cell * 4 + 1] = vy
                pixels[cell * 4 + 2] = dye[cell]
                pixels[cell * 4 + 3] = solid[cell] ? 1 : 0
                if !solid[cell], x > 0, x < width - 1, y > 0, y < height - 1 {
                    let speed = sqrt(vx * vx + vy * vy)
                    peak = max(peak, speed)
                    sum += Double(speed)
                    let div = (u[x + 1 + y * (width + 1)] - u[x + y * (width + 1)]) / dx
                        + (v[x + (y + 1) * width] - v[x + y * width]) / dy
                    residual += Double(abs(div))
                    count += 1
                }
            }
        }
        return .init(width: width, height: height, pixels: pixels, peakSpeed: Double(peak),
                     meanSpeed: sum / Double(max(1, count)), divergence: residual / Double(max(1, count)), time: time)
    }

    private func bound(_ value: Double, _ limits: ClosedRange<Double>) -> Double {
        min(limits.upperBound, max(limits.lowerBound, value.isFinite ? value : limits.lowerBound))
    }

    private mutating func rebuildBody(_ inputs: RoomFlowInputs) {
        let cx = bound(inputs.bodyX, 0.22...0.78), cy = bound(inputs.bodyY, 0.22...0.78)
        let angle = bound(inputs.angle, -40...40)
        guard inputs.body != lastBody || cx != lastX || cy != lastY || angle != lastAngle else { return }
        lastBody = inputs.body; lastX = cx; lastY = cy; lastAngle = angle
        let radians = -angle * .pi / 180
        let cosine = cos(radians), sine = sin(radians)
        for y in 0..<height {
            for x in 0..<width {
                let px = (Double(x) + 0.5) / Double(width) * domainWidth - cx * domainWidth
                let py = (Double(y) + 0.5) / Double(height) * domainHeight - cy * domainHeight
                let rx = px * cosine - py * sine
                let ry = px * sine + py * cosine
                let inside: Bool
                switch inputs.body {
                case .circle: inside = rx * rx + ry * ry < 0.85 * 0.85
                case .block: inside = abs(rx) < 0.8 && abs(ry) < 0.8
                case .car:
                    let base = abs(rx) < 1.55 && ry > -0.25 && ry < 0.32
                    let roof = rx > -0.6 && rx < 0.9 && ry >= 0.32 && ry < 0.8 - 0.28 * abs(rx)
                    inside = base || roof
                case .wing:
                    let t = (rx + 1.5) / 3
                    if t >= 0, t <= 1 {
                        let thickness = 5 * 0.15 * 3 * (0.2969 * sqrt(t) - 0.126 * t - 0.3516 * t * t
                            + 0.2843 * t * t * t - 0.1036 * t * t * t * t)
                        let camber = 0.12 * sin(.pi * t)
                        inside = abs(ry - camber) < max(0.055, thickness)
                    } else { inside = false }
                }
                let index = x + y * width
                solid[index] = y == 0 || y == height - 1 || inside
                if solid[index] { dye[index] = 0; pressure[index] = 0 }
            }
        }
    }

    private func cellSolid(_ x: Int, _ y: Int) -> Bool {
        if y < 0 || y >= height { return true }
        if x < 0 || x >= width { return false }
        return solid[x + y * width]
    }

    private mutating func boundaries(_ speed: Float) {
        for y in 0..<height {
            for x in 0...width {
                let index = x + y * (width + 1)
                if cellSolid(x - 1, y) || cellSolid(x, y) { u[index] = 0 }
                else if x == 0 { u[index] = speed }
                else if x == width { u[index] = max(0, u[index - 1]) }
            }
        }
        for y in 0...height {
            for x in 0..<width {
                let index = x + y * width
                if cellSolid(x, y - 1) || cellSolid(x, y) { v[index] = 0 }
                else if x == 0 || x == width - 1 { v[index] = 0 }
            }
        }
    }

    private mutating func advectVelocity(dt: Float) {
        let oldU = u, oldV = v
        let dx = Float(domainWidth) / Float(width), dy = Float(domainHeight) / Float(height)
        for y in 1..<(height - 1) {
            for x in 1..<width {
                if cellSolid(x - 1, y) || cellSolid(x, y) { continue }
                let px = Float(x) * dx, py = (Float(y) + 0.5) * dy
                let vx = sample(oldU, columns: width + 1, rows: height, x: px / dx, y: py / dy - 0.5)
                let vy = sample(oldV, columns: width, rows: height + 1, x: px / dx - 0.5, y: py / dy)
                let i = x + y * (width + 1)
                let advected = sample(oldU, columns: width + 1, rows: height,
                                      x: (px - dt * vx) / dx, y: (py - dt * vy) / dy - 0.5)
                u[i] = advected
            }
        }
        for y in 1..<height {
            for x in 1..<(width - 1) {
                if cellSolid(x, y - 1) || cellSolid(x, y) { continue }
                let px = (Float(x) + 0.5) * dx, py = Float(y) * dy
                let vx = sample(oldU, columns: width + 1, rows: height, x: px / dx, y: py / dy - 0.5)
                let vy = sample(oldV, columns: width, rows: height + 1, x: px / dx - 0.5, y: py / dy)
                let i = x + y * width
                let advected = sample(oldV, columns: width, rows: height + 1,
                                      x: (px - dt * vx) / dx - 0.5, y: (py - dt * vy) / dy)
                v[i] = advected
            }
        }
    }

    private mutating func diffuseVelocity(dt: Float) {
        let oldU = u, oldV = v
        let dx = Float(domainWidth) / Float(width), dy = Float(domainHeight) / Float(height)
        let ax = Float(viscosity) * dt / (dx * dx)
        let ay = Float(viscosity) * dt / (dy * dy)
        // Diffuse the advected field with a convex stencil. Applying the old-field
        // Laplacian to the backtraced field can amplify alternating cell velocities.
        for y in 1..<(height - 1) {
            for x in 1..<width where !cellSolid(x - 1, y) && !cellSolid(x, y) {
                let i = x + y * (width + 1)
                u[i] = oldU[i] * (1 - 2 * ax - 2 * ay)
                    + ax * (oldU[i - 1] + oldU[i + 1])
                    + ay * (oldU[i - width - 1] + oldU[i + width + 1])
            }
        }
        for y in 1..<height {
            for x in 1..<(width - 1) where !cellSolid(x, y - 1) && !cellSolid(x, y) {
                let i = x + y * width
                v[i] = oldV[i] * (1 - 2 * ax - 2 * ay)
                    + ax * (oldV[i - 1] + oldV[i + 1])
                    + ay * (oldV[i - width] + oldV[i + width])
            }
        }
    }

    private mutating func project(iterations: Int) {
        let nx = width, ny = height
        let dx = Float(domainWidth) / Float(nx), dy = Float(domainHeight) / Float(ny)
        let sx = 1 / (dx * dx), sy = 1 / (dy * dy)
        projectionDivergenceBefore = divergenceMagnitude()
        var divergence = [Float](repeating: 0, count: nx * ny)
        for y in 1..<(ny - 1) {
            for x in 0..<(nx - 1) where !solid[x + y * nx] {
                divergence[x + y * nx] = ((u[x + 1 + y * (nx + 1)] - u[x + y * (nx + 1)]) / dx
                    + (v[x + (y + 1) * nx] - v[x + y * nx]) / dy)
            }
        }
        // Solve a fresh pressure impulse, Laplacian(phi) = div(u). A stale physical
        // pressure warm start across tiny variable timesteps injected correction energy.
        pressure = [Float](repeating: 0, count: nx * ny)
        var next = pressure
        for _ in 0..<iterations {
            for y in 1..<(ny - 1) {
                for x in 0..<(nx - 1) {
                    let index = x + y * nx
                    guard !solid[index] else { next[index] = 0; continue }
                    var sum: Float = 0, coefficient: Float = 0
                    if x > 0, !solid[index - 1] { sum += pressure[index - 1] * sx; coefficient += sx }
                    if !solid[index + 1] { sum += pressure[index + 1] * sx; coefficient += sx }
                    if !solid[index - nx] { sum += pressure[index - nx] * sy; coefficient += sy }
                    if !solid[index + nx] { sum += pressure[index + nx] * sy; coefficient += sy }
                    next[index] = coefficient > 0 ? (sum - divergence[index]) / coefficient : 0
                }
            }
            swap(&pressure, &next)
        }
        for y in 1..<(ny - 1) {
            for x in 1..<nx where !solid[x - 1 + y * nx] && !solid[x + y * nx] {
                u[x + y * (nx + 1)] -= (pressure[x + y * nx] - pressure[x - 1 + y * nx]) / dx
            }
        }
        for y in 1..<ny {
            for x in 0..<nx where !solid[x + (y - 1) * nx] && !solid[x + y * nx] {
                v[x + y * nx] -= (pressure[x + y * nx] - pressure[x + (y - 1) * nx]) / dy
            }
        }
        projectionDivergenceAfter = divergenceMagnitude()
    }

    private func divergenceMagnitude() -> Double {
        let dx = Float(domainWidth) / Float(width), dy = Float(domainHeight) / Float(height)
        var total = 0.0, count = 0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) where !solid[x + y * width] {
                let divergence = (u[x + 1 + y * (width + 1)] - u[x + y * (width + 1)]) / dx
                    + (v[x + (y + 1) * width] - v[x + y * width]) / dy
                total += Double(abs(divergence))
                count += 1
            }
        }
        return total / Double(max(1, count))
    }

    private mutating func advectDye(dt: Float) {
        let old = dye
        let dx = Float(domainWidth) / Float(width), dy = Float(domainHeight) / Float(height)
        for y in 1..<(height - 1) {
            for x in 0..<width {
                let index = x + y * width
                guard !solid[index] else { dye[index] = 0; continue }
                if x < 2 {
                    let stripe = (y / 4) % 2 == 0
                    dye[index] = stripe ? Float(0.7 + 0.25 * sin(time * 4)) : 0.06
                } else {
                    let vx = (u[x + y * (width + 1)] + u[x + 1 + y * (width + 1)]) * 0.5
                    let vy = (v[x + y * width] + v[x + (y + 1) * width]) * 0.5
                    dye[index] = max(0, min(1, sample(old, columns: width, rows: height,
                                                     x: Float(x) - dt * vx / dx, y: Float(y) - dt * vy / dy)))
                }
            }
        }
    }

    private func sample(_ array: [Float], columns: Int, rows: Int, x: Float, y: Float) -> Float {
        let px = max(0, min(Float(columns - 1) - 0.0001, x))
        let py = max(0, min(Float(rows - 1) - 0.0001, y))
        let x0 = Int(px), y0 = Int(py)
        let fx = px - Float(x0), fy = py - Float(y0)
        let a = array[x0 + y0 * columns] * (1 - fx) + array[x0 + 1 + y0 * columns] * fx
        let b = array[x0 + (y0 + 1) * columns] * (1 - fx) + array[x0 + 1 + (y0 + 1) * columns] * fx
        return a * (1 - fy) + b * fy
    }
}
