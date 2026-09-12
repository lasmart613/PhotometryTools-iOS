import SwiftUI

/// Candela VBeam wavelength via interference-filter Δ% table (`wavelength.html`).
struct WavelengthCalculatorView: View {
    /// Tenths of a nanometer (−5…+5 → −0.5…+0.5), avoiding binary `0.1` tag mismatches.
    @AppStorage("correctionFactorTenths") private var correctionTenths = 0
    @State private var step = 1
    @State private var energyOut1 = ""
    @State private var hd1_1 = ""
    @State private var energyOut2 = ""
    @State private var hd1_2 = ""
    @State private var validation: String?

    private var correction: Double {
        Double(correctionTenths) / 10
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    ForEach(1...3, id: \.self) { index in
                        Circle()
                            .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: 10, height: 10)
                            .accessibilityLabel("Step \(index)\(index == step ? ", current" : "")")
                    }
                }
                .frame(maxWidth: .infinity)
            }

            switch step {
            case 1:
                correctionStep
            case 2:
                withoutFilterStep
            default:
                withFilterStep
            }
        }
        .navigationTitle("Wavelength")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var correctionStep: some View {
        Group {
            Section {
                Text("Set the correction factor printed on your interference filter. Only needs to be set once.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("Correction factor (nm)", selection: $correctionTenths) {
                    ForEach(-5...5, id: \.self) { tenths in
                        Text(Self.correctionLabel(Double(tenths) / 10)).tag(tenths)
                    }
                }
                Text(correctionStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Filter correction")
            }

            Section {
                Button("Next: Readings Without Filter") {
                    step = 2
                    validation = nil
                }
            }
        }
    }

    private var withoutFilterStep: some View {
        Group {
            Section {
                Text("Take readings WITHOUT the filter installed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                CalculatorNumericField(
                    title: "Energy out of fiber (mJ)",
                    placeholder: "Enter energy",
                    text: $energyOut1
                )
                CalculatorNumericField(
                    title: "Head Detector 1 — HD1 (mJ)",
                    placeholder: "Enter HD1 reading",
                    text: $hd1_1
                )
            } header: {
                Text("Without filter")
            }

            Section {
                CalculatorValidationBanner(message: validation)
                HStack {
                    Button("Back") {
                        step = 1
                        validation = nil
                    }
                    Spacer()
                    Button("Next: With Filter") {
                        if CalculatorNumber.positive(energyOut1) == nil
                            || CalculatorNumber.positive(hd1_1) == nil {
                            validation = CalculatorValidation.enterValidReadings.message
                        } else {
                            validation = nil
                            step = 3
                        }
                    }
                }
            }
        }
    }

    private var withFilterStep: some View {
        Group {
            Section {
                Text("Take readings WITH the filter installed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                CalculatorNumericField(
                    title: "Energy out of fiber (mJ)",
                    placeholder: "Enter energy",
                    text: $energyOut2
                )
                CalculatorNumericField(
                    title: "Head Detector 1 — HD1 (mJ)",
                    placeholder: "Enter HD1 reading",
                    text: $hd1_2
                )
            } header: {
                Text("With filter")
            }

            Section {
                CalculatorValidationBanner(message: validation)
                HStack {
                    Button("Back") {
                        step = 2
                        validation = nil
                    }
                    Spacer()
                    Button("Calculate Wavelength") {
                        calculate()
                    }
                }
                Button("New Calculation") {
                    energyOut1 = ""
                    hd1_1 = ""
                    energyOut2 = ""
                    hd1_2 = ""
                    validation = nil
                    step = 2
                }
            }

            if case .success(let result) = currentResult {
                Section {
                    CalculatorResultCard(
                        title: "Calculated Wavelength",
                        value: "\(CalculatorNumber.format(result.wavelengthNM, digits: 2)) nm",
                        details: [
                            ("Without filter", "\(CalculatorNumber.format(result.ratioWithoutFilter, digits: 4)) (\(CalculatorNumber.format(result.energyOutWithoutMJ, digits: 2))/\(CalculatorNumber.format(result.hd1WithoutMJ, digits: 2)))"),
                            ("With filter", "\(CalculatorNumber.format(result.ratioWithFilter, digits: 4)) (\(CalculatorNumber.format(result.energyOutWithMJ, digits: 2))/\(CalculatorNumber.format(result.hd1WithMJ, digits: 2)))"),
                            ("Delta%", "\(CalculatorNumber.format(result.deltaPercent, digits: 2))%"),
                            ("Base wavelength", "\(CalculatorNumber.format(result.baseWavelengthNM, digits: 2)) nm"),
                            ("Correction", Self.signedCorrection(result.correctionNM))
                        ],
                        shareText: shareText(result)
                    )
                }
            }
        }
    }

    private var currentResult: Result<PhotometryMath.WavelengthResult, CalculatorValidation> {
        PhotometryMath.vbeamWavelength(
            energyOutWithoutMJ: CalculatorNumber.positive(energyOut1),
            hd1WithoutMJ: CalculatorNumber.positive(hd1_1),
            energyOutWithMJ: CalculatorNumber.positive(energyOut2),
            hd1WithMJ: CalculatorNumber.positive(hd1_2),
            correctionNM: correction
        )
    }

    private var correctionStatus: String {
        if correction == 0 { return "No correction factor applied" }
        return "Correction factor: \(Self.signedCorrection(correction))"
    }

    private func calculate() {
        switch currentResult {
        case .success:
            validation = nil
        case .failure(let error):
            validation = error.message
        }
    }

    private func shareText(_ result: PhotometryMath.WavelengthResult) -> String {
        """
        Calculated Wavelength: \(CalculatorNumber.format(result.wavelengthNM, digits: 2)) nm
        Without filter: \(CalculatorNumber.format(result.ratioWithoutFilter, digits: 4)) (\(result.energyOutWithoutMJ)/\(result.hd1WithoutMJ))
        With filter: \(CalculatorNumber.format(result.ratioWithFilter, digits: 4)) (\(result.energyOutWithMJ)/\(result.hd1WithMJ))
        Delta%: \(CalculatorNumber.format(result.deltaPercent, digits: 2))%
        Base wavelength: \(CalculatorNumber.format(result.baseWavelengthNM, digits: 2)) nm
        Correction: \(Self.signedCorrection(result.correctionNM))
        """
    }

    private static func correctionLabel(_ value: Double) -> String {
        if value == 0 { return "0.0 nm" }
        if value > 0 { return String(format: "+%.1f nm", value) }
        return String(format: "%.1f nm", value)
    }

    private static func signedCorrection(_ value: Double) -> String {
        if value > 0 { return String(format: "+%.1f nm", value) }
        return String(format: "%.1f nm", value)
    }
}

#Preview {
    NavigationStack {
        WavelengthCalculatorView()
    }
}
