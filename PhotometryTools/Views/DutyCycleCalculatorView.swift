import SwiftUI

/// Pulsed-laser duty cycle. Matches `duty_cycle.html`.
struct DutyCycleCalculatorView: View {
    @State private var pulseWidthText = ""
    @State private var offTimeText = ""
    @State private var ppsText = ""
    @State private var showValidation = false

    private var evaluation: Result<PhotometryMath.DutyCycle, CalculatorValidation> {
        PhotometryMath.dutyCycle(
            pulseWidthMS: CalculatorNumber.parse(pulseWidthText),
            offTimeMS: CalculatorNumber.parse(offTimeText),
            pulsesPerSecond: CalculatorNumber.parse(ppsText)
        )
    }

    var body: some View {
        Form {
            Section {
                CalculatorNumericField(
                    title: "Pulse width / on-time (ms)",
                    placeholder: "e.g. 10",
                    text: $pulseWidthText
                )
            } header: {
                Text("On-time")
            }

            Section {
                Text("Enter one of the following.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                CalculatorNumericField(
                    title: "Off-time (ms)",
                    placeholder: "e.g. 90",
                    text: $offTimeText
                )
                CalculatorNumericField(
                    title: "Pulses per second (Hz)",
                    placeholder: "e.g. 10",
                    text: $ppsText
                )
            } header: {
                Text("Period")
            } footer: {
                Text("Off-time or PPS, not both. Period from PPS is 1000 ÷ Hz.")
            }

            Section {
                Button("Calculate Duty Cycle") {
                    showValidation = true
                }
                CalculatorValidationBanner(message: showValidation ? validationMessage : nil)
            }

            if case .success(let result) = evaluation {
                Section {
                    CalculatorResultCard(
                        title: "Duty Cycle",
                        value: "\(CalculatorNumber.format(result.dutyCyclePercent, digits: 2))%",
                        details: [
                            ("Pulse Width", "\(CalculatorNumber.format(result.pulseWidthMS, digits: 3)) ms"),
                            ("Off-Time", "\(CalculatorNumber.format(result.offTimeMS, digits: 3)) ms"),
                            ("Period", "\(CalculatorNumber.format(result.periodMS, digits: 3)) ms"),
                            ("Frequency", "\(CalculatorNumber.format(result.frequencyHz, digits: 2)) Hz"),
                            ("Duty Cycle", "\(CalculatorNumber.format(result.dutyCyclePercent, digits: 2))%")
                        ],
                        shareText: """
                        Duty Cycle: \(CalculatorNumber.format(result.dutyCyclePercent, digits: 2))%
                        Pulse Width: \(CalculatorNumber.format(result.pulseWidthMS, digits: 3)) ms
                        Off-Time: \(CalculatorNumber.format(result.offTimeMS, digits: 3)) ms
                        Period: \(CalculatorNumber.format(result.periodMS, digits: 3)) ms
                        Frequency: \(CalculatorNumber.format(result.frequencyHz, digits: 2)) Hz
                        """
                    )
                }
            }

            Section("Formula") {
                CalculatorFormulaBox(lines: [
                    "Duty Cycle (%) = Pulse Width ÷ Period × 100",
                    "Period = Pulse Width + Off-Time",
                    "Period (ms) = 1000 ÷ PPS"
                ])
            }
        }
        .navigationTitle("Duty Cycle")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pulseWidthText) { _, _ in showValidation = false }
        .onChange(of: offTimeText) { _, _ in showValidation = false }
        .onChange(of: ppsText) { _, _ in showValidation = false }
    }

    private var validationMessage: String? {
        if case .failure(let error) = evaluation {
            return error.message
        }
        return nil
    }
}

#Preview {
    NavigationStack {
        DutyCycleCalculatorView()
    }
}
