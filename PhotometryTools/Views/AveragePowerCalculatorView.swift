import SwiftUI

/// Energy × frequency / power ÷ frequency. Matches `avgpower.html`.
struct AveragePowerCalculatorView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case forward
        case reverse
        var id: String { rawValue }
        var title: String {
            switch self {
            case .forward: return "Energy → Power"
            case .reverse: return "Power → Energy"
            }
        }
    }

    @State private var mode: Mode = .forward
    @State private var energyText = ""
    @State private var energyUnit: EnergyUnit = .millijoule
    @State private var powerText = ""
    @State private var frequencyText = ""
    @State private var showValidation = false

    private var evaluation: Result<DisplayResult, CalculatorValidation> {
        let freq = CalculatorNumber.positive(frequencyText)
        switch mode {
        case .forward:
            switch PhotometryMath.averagePowerWatts(
                energy: CalculatorNumber.positive(energyText) ?? 0,
                unit: energyUnit,
                frequencyHz: freq ?? 0
            ) {
            case .success(let watts):
                return .success(
                    .power(
                        watts: watts,
                        energyDisplay: "\(energyText) \(energyUnit.rawValue)",
                        frequencyHz: freq ?? 0
                    )
                )
            case .failure(let error):
                return .failure(error)
            }
        case .reverse:
            switch PhotometryMath.pulseEnergyJoules(
                averagePowerW: CalculatorNumber.positive(powerText) ?? 0,
                frequencyHz: freq ?? 0
            ) {
            case .success(let joules):
                let display: String
                switch energyUnit {
                case .millijoule:
                    display = "\(CalculatorNumber.format(joules * 1000, digits: 3)) mJ"
                case .joule:
                    display = "\(CalculatorNumber.format(joules, digits: 4)) J"
                }
                return .success(
                    .energy(
                        display: display,
                        powerW: CalculatorNumber.positive(powerText) ?? 0,
                        frequencyHz: freq ?? 0
                    )
                )
            case .failure(let error):
                return .failure(error)
            }
        }
    }

    var body: some View {
        Form {
            Section("Mode") {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }

            if mode == .forward {
                Section("Pulse energy") {
                    CalculatorNumericField(
                        title: "Energy",
                        placeholder: "e.g. 50",
                        text: $energyText
                    )
                    Picker("Unit", selection: $energyUnit) {
                        ForEach(EnergyUnit.allCases) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            } else {
                Section("Average power") {
                    CalculatorNumericField(
                        title: "Average power (W)",
                        placeholder: "e.g. 5",
                        text: $powerText
                    )
                    Picker("Energy unit", selection: $energyUnit) {
                        ForEach(EnergyUnit.allCases) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section {
                CalculatorNumericField(
                    title: "Repetition rate (Hz)",
                    placeholder: "e.g. 10",
                    text: $frequencyText
                )
            }

            Section {
                Button("Calculate") {
                    showValidation = true
                }
                CalculatorValidationBanner(message: showValidation ? validationMessage : nil)
            }

            if case .success(let result) = evaluation {
                Section {
                    CalculatorResultCard(
                        title: result.title,
                        value: result.value,
                        details: result.details,
                        shareText: result.shareText
                    )
                }
            }

            Section("Formula") {
                CalculatorFormulaBox(lines: [
                    "Avg Power (W) = Energy (J) × Frequency (Hz)",
                    "Pulse Energy (J) = Avg Power (W) ÷ Frequency (Hz)",
                    "1 J = 1000 mJ"
                ])
            }
        }
        .navigationTitle("Average Power")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: mode) { _, _ in showValidation = false }
    }

    private var validationMessage: String? {
        if case .failure(let error) = evaluation {
            return error.message
        }
        return nil
    }

    private enum DisplayResult {
        case power(watts: Double, energyDisplay: String, frequencyHz: Double)
        case energy(display: String, powerW: Double, frequencyHz: Double)

        var title: String {
            switch self {
            case .power: return "Average Power"
            case .energy: return "Pulse Energy"
            }
        }

        var value: String {
            switch self {
            case .power(let watts, _, _):
                return "\(CalculatorNumber.format(watts, digits: 3)) W"
            case .energy(let display, _, _):
                return display
            }
        }

        var details: [(String, String)] {
            switch self {
            case .power(let watts, let energyDisplay, let frequencyHz):
                return [
                    ("Energy", energyDisplay),
                    ("Frequency", "\(CalculatorNumber.format(frequencyHz, digits: 1)) Hz"),
                    ("Avg Power", "\(CalculatorNumber.format(watts, digits: 3)) W")
                ]
            case .energy(let display, let powerW, let frequencyHz):
                return [
                    ("Avg Power", "\(CalculatorNumber.format(powerW, digits: 2)) W"),
                    ("Frequency", "\(CalculatorNumber.format(frequencyHz, digits: 1)) Hz"),
                    ("Pulse Energy", display)
                ]
            }
        }

        var shareText: String {
            let rows = details.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
            return "\(title): \(value)\n\(rows)"
        }
    }
}

#Preview {
    NavigationStack {
        AveragePowerCalculatorView()
    }
}
