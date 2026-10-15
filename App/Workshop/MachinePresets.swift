import MechanicalCore

struct MachinePreset: Identifiable {
    let name: String
    let values: [String: Double]
    var id: String { name }
    static func presets(for kind: ExperimentKind) -> [MachinePreset] {
        switch kind {
        case .combustion:
            [MachinePreset(name: "City car · 1 L / 3 cylinders", values: ["displacement": 1, "cylinders": 3, "rpm": 2400, "throttle": 55, "compression": 10]),
             MachinePreset(name: "Touring car · 2 L / 4 cylinders", values: ["displacement": 2, "cylinders": 4, "rpm": 3000, "throttle": 70, "compression": 10.5]),
             MachinePreset(name: "Sports car · 5 L / V8", values: ["displacement": 5, "cylinders": 8, "rpm": 5500, "throttle": 100, "compression": 11]),
             MachinePreset(name: "Supercar · 6.5 L / V12", values: ["displacement": 6.5, "cylinders": 12, "rpm": 8000, "throttle": 100, "compression": 12])]
        case .diesel:
            [MachinePreset(name: "Compact diesel · 1.5 L", values: ["displacement": 1.5, "rpm": 1800, "throttle": 70, "boost": 1, "compression": 18]),
             MachinePreset(name: "Pickup diesel · 3 L", values: ["displacement": 3, "rpm": 2400, "throttle": 85, "boost": 1.5, "compression": 17]),
             MachinePreset(name: "Heavy transport · 12 L", values: ["displacement": 12, "rpm": 1800, "throttle": 100, "boost": 2, "compression": 18])]
        case .electricMotor:
            [MachinePreset(name: "Small electric drive · 48 V", values: ["voltage": 48, "currentLimit": 40, "resistance": 0.15, "motorConstant": 0.1, "rpm": 2200]),
             MachinePreset(name: "Electric car drive · 400 V", values: ["voltage": 400, "currentLimit": 250, "resistance": 0.1, "motorConstant": 0.55, "rpm": 4500]),
             MachinePreset(name: "High-torque electric drive", values: ["voltage": 400, "currentLimit": 300, "resistance": 0.08, "motorConstant": 0.85, "rpm": 3600])]
        default: []
        }
    }
}
