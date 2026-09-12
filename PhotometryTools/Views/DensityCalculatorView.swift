import SwiftUI

/// Unified fluence / irradiance calculator. Fluence mode matches legacy
/// `fluence.html`; both modes match `density_calculator.html`.
struct DensityCalculatorView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case fluence
        case irradiance
        var id: String { rawValue }
        var title: String {
            switch self {
            case .fluence: return "Fluence"
            case .irradiance: return "Irradiance"
            }
        }
    }

    enum Waveform: String, CaseIterable, Identifiable {
        case cw
        case pulsed
        var id: String { rawValue }
        var title: String {
            switch self {
            case .cw: return "CW"
            case .pulsed: return "Pulsed"
            }
        }
    }

    enum PulsedInput: String, CaseIterable, Identifiable {
        case energy
        case fluence
        var id: String { rawValue }
        var title: String {
            switch self {
            case .energy: return "Energy / pulse"
            case .fluence: return "Fluence / pulse"
            }
        }
    }

    enum ShapeKind: String, CaseIterable, Identifiable {
        case circular
        case rectangular
        var id: String { rawValue }
        var title: String {
            switch self {
            case .circular: return "Circular"
            case .rectangular: return "Rectangular"
            }
        }
    }

    enum RectKind: String, CaseIterable, Identifiable {
        case square
        case rectangle
        var id: String { rawValue }
        var title: String {
            switch self {
            case .square: return "Square"
            case .rectangle: return "Rectangle"
            }
        }
    }

    let initialMode: Mode
    let navigationTitleText: String

    @State private var mode: Mode
    @State private var waveform: Waveform = .cw
    @State private var pulsedInput: PulsedInput = .energy
    @State private var shape: ShapeKind = .circular
    @State private var rectKind: RectKind = .square
    @State private var diameterMM = PhotometryMath.defaultCircularDiameterMM
    @State private var sideMM = PhotometryMath.defaultRectangularMM
    @State private var lengthMM = PhotometryMath.defaultRectangularMM
    @State private var widthMM = PhotometryMath.defaultRectangularMM
    @State private var valueText = ""
    @State private var energyPerPulseText = ""
    @State private var fluencePerPulseText = ""
    @State private var repRateText = ""
    @State private var showValidation = false

    init(initialMode: Mode = .fluence, title: String = "Density") {
        self.initialMode = initialMode
        self.navigationTitleText = title
        _mode = State(initialValue: initialMode)
    }

    private var area: Double {
        PhotometryMath.areaCm2(currentShape)
    }

    private var currentShape: BeamShape {
        switch shape {
        case .circular:
            return .circular(diameterMM: Double(diameterMM))
        case .rectangular:
            switch rectKind {
            case .square:
                return .square(sideMM: Double(sideMM))
            case .rectangle:
                return .rectangle(lengthMM: Double(lengthMM), widthMM: Double(widthMM))
            }
        }
    }

    private var isPulsedIrradiance: Bool {
        mode == .irradiance && waveform == .pulsed
    }

    private var evaluation: Result<DisplayResult, CalculatorValidation> {
        if isPulsedIrradiance {
            let rate = CalculatorNumber.positive(repRateText)
            if pulsedInput == .energy {
                switch PhotometryMath.pulsedIrradianceFromEnergy(
                    energyJ: CalculatorNumber.positive(energyPerPulseText) ?? 0,
                    repRateHz: rate ?? 0,
                    areaCm2: area
                ) {
                case .success(let pulsed):
                    return .success(.pulsed(pulsed))
                case .failure(let error):
                    return .failure(error)
                }
            }
            switch PhotometryMath.pulsedIrradianceFromFluence(
                fluenceJPerCm2: CalculatorNumber.positive(fluencePerPulseText) ?? 0,
                repRateHz: rate ?? 0,
                areaCm2: area
            ) {
            case .success(let pulsed):
                return .success(.pulsed(pulsed))
            case .failure(let error):
                return .failure(error)
            }
        }

        let value = CalculatorNumber.positive(valueText) ?? 0
        switch mode {
        case .fluence:
            switch PhotometryMath.fluenceJPerCm2(energyJ: value, areaCm2: area) {
            case .success(let fluence):
                return .success(.single(kind: .fluence, input: value, result: fluence, area: area))
            case .failure(let error):
                return .failure(error)
            }
        case .irradiance:
            switch PhotometryMath.irradianceWPerCm2(powerW: value, areaCm2: area) {
            case .success(let irradiance):
                return .success(.single(kind: .irradiance, input: value, result: irradiance, area: area))
            case .failure(let error):
                return .failure(error)
            }
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                if mode == .irradiance {
                    Picker("Waveform", selection: $waveform) {
                        ForEach(Waveform.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Output")
            } footer: {
                Text(mode == .fluence
                     ? "Energy density in J/cm² (legacy Fluence calculator)."
                     : "Power density in W/cm². Pulsed uses energy or fluence per pulse × rep rate.")
            }

            Section("Beam shape") {
                Picker("Shape", selection: $shape) {
                    ForEach(ShapeKind.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                if shape == .circular {
                    Picker("Diameter", selection: $diameterMM) {
                        ForEach(PhotometryMath.spotSizesMM, id: \.self) { size in
                            Text("\(size) mm").tag(size)
                        }
                    }
                } else {
                    Picker("Rectangle type", selection: $rectKind) {
                        ForEach(RectKind.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    if rectKind == .square {
                        Picker("Side length", selection: $sideMM) {
                            ForEach(PhotometryMath.spotSizesMM, id: \.self) { size in
                                Text("\(size) mm").tag(size)
                            }
                        }
                    } else {
                        Picker("Length", selection: $lengthMM) {
                            ForEach(PhotometryMath.spotSizesMM, id: \.self) { size in
                                Text("\(size) mm").tag(size)
                            }
                        }
                        Picker("Width", selection: $widthMM) {
                            ForEach(PhotometryMath.spotSizesMM, id: \.self) { size in
                                Text("\(size) mm").tag(size)
                            }
                        }
                    }
                }
                LabeledContent("Spot area", value: "\(CalculatorNumber.format(area, digits: 4)) cm²")
            }

            if isPulsedIrradiance {
                Section("Per-pulse input") {
                    Picker("Input", selection: $pulsedInput) {
                        ForEach(PulsedInput.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    if pulsedInput == .energy {
                        CalculatorNumericField(
                            title: "Energy per pulse (J)",
                            placeholder: "e.g. 2.5",
                            text: $energyPerPulseText
                        )
                    } else {
                        CalculatorNumericField(
                            title: "Fluence per pulse (J/cm²)",
                            placeholder: "e.g. 12.5",
                            text: $fluencePerPulseText
                        )
                    }
                    CalculatorNumericField(
                        title: "Repetition rate (Hz)",
                        placeholder: "e.g. 10",
                        text: $repRateText
                    )
                }
            } else {
                Section(mode == .fluence ? "Energy" : "Power") {
                    CalculatorNumericField(
                        title: mode == .fluence ? "Energy (J)" : "Peak power (W)",
                        placeholder: "e.g. 1.5",
                        text: $valueText
                    )
                }
            }

            Section {
                Button(calculateTitle) {
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
                CalculatorFormulaBox(lines: formulaLines)
            }
        }
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: mode) { _, _ in
            showValidation = false
            if mode == .fluence { waveform = .cw }
        }
        .onChange(of: waveform) { _, _ in showValidation = false }
        .onChange(of: pulsedInput) { _, _ in showValidation = false }
        .onChange(of: shape) { _, _ in showValidation = false }
        .onChange(of: rectKind) { _, _ in showValidation = false }
    }

    private var calculateTitle: String {
        if isPulsedIrradiance { return "Calculate Average Irradiance" }
        return mode == .fluence ? "Calculate Fluence" : "Calculate Irradiance"
    }

    private var validationMessage: String? {
        if case .failure(let error) = evaluation {
            return error.message
        }
        return nil
    }

    private var formulaLines: [String] {
        if isPulsedIrradiance {
            return [
                "Avg Power (W) = Energy per pulse (J) × Rep Rate (Hz)",
                "Avg Irradiance = Avg Power ÷ Area",
                "— OR —",
                "Avg Irradiance (W/cm²) = Fluence per pulse (J/cm²) × Rep Rate (Hz)"
            ]
        }
        if mode == .fluence {
            return [
                "Fluence (J/cm²) = Energy (J) ÷ Area (cm²)",
                "Circular Area = π × (d÷2)² ÷ 100",
                "Square Area = s² ÷ 100",
                "Rect Area = L × W ÷ 100"
            ]
        }
        return [
            "Irradiance (W/cm²) = Power (W) ÷ Area (cm²)",
            "Circular Area = π × (d÷2)² ÷ 100",
            "Square Area = s² ÷ 100",
            "Rect Area = L × W ÷ 100"
        ]
    }

    private enum DisplayResult {
        case single(kind: Mode, input: Double, result: Double, area: Double)
        case pulsed(PhotometryMath.PulsedIrradiance)

        var title: String {
            switch self {
            case .single(let kind, _, _, _):
                return kind == .fluence ? "Fluence" : "Irradiance"
            case .pulsed:
                return "Avg Irradiance"
            }
        }

        var value: String {
            switch self {
            case .single(_, _, let result, _):
                return "\(CalculatorNumber.format(result, digits: 2)) \(self.unit)"
            case .pulsed(let pulsed):
                return "\(CalculatorNumber.format(pulsed.avgIrradianceWPerCm2, digits: 2)) W/cm²"
            }
        }

        private var unit: String {
            switch self {
            case .single(let kind, _, _, _):
                return kind == .fluence ? "J/cm²" : "W/cm²"
            case .pulsed:
                return "W/cm²"
            }
        }

        var details: [(String, String)] {
            switch self {
            case .single(let kind, let input, let result, let area):
                return [
                    (kind == .fluence ? "Energy" : "Power",
                     "\(CalculatorNumber.format(input, digits: 2)) \(kind == .fluence ? "J" : "W")"),
                    ("Spot Area", "\(CalculatorNumber.format(area, digits: 4)) cm²"),
                    (kind == .fluence ? "Fluence" : "Irradiance",
                     "\(CalculatorNumber.format(result, digits: 2)) \(kind == .fluence ? "J/cm²" : "W/cm²")")
                ]
            case .pulsed(let pulsed):
                return [
                    ("Per-Pulse", "\(CalculatorNumber.format(pulsed.perPulseValue, digits: 2)) \(pulsed.perPulseUnit)"),
                    ("Rep Rate", "\(CalculatorNumber.format(pulsed.repRateHz, digits: 1)) Hz"),
                    ("Avg Power", "\(CalculatorNumber.format(pulsed.avgPowerW, digits: 2)) W"),
                    ("Spot Area", "\(CalculatorNumber.format(pulsed.areaCm2, digits: 4)) cm²"),
                    ("Avg Irradiance", "\(CalculatorNumber.format(pulsed.avgIrradianceWPerCm2, digits: 2)) W/cm²")
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
        DensityCalculatorView(initialMode: .fluence)
    }
}
