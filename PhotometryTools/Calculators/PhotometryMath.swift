import Foundation

/// Shared number parsing and HTML-matching formatters for the native calculators.
enum CalculatorNumber {
    /// Parse a field the way the HTML `parseFloat` inputs are intended:
    /// trimmed, comma-as-decimal, finite. Empty → `nil`.
    static func parse(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    /// HTML treats empty / NaN / ≤ 0 as “not a usable positive value”.
    static func positive(_ raw: String) -> Double? {
        guard let value = parse(raw), value > 0 else { return nil }
        return value
    }

    static func format(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }
}

/// Validation copy taken from the bundled HTML calculators (`showToast` strings).
enum CalculatorValidation: Equatable, Sendable {
    case enterValidPositiveValues
    case enterValidEnergyPerPulse
    case enterValidFluencePerPulse
    case enterValidRepRateAndSpotSize
    case enterValidPulseWidth
    case enterOffTimeOrPPS
    case enterOnlyOneOffTimeOrPPS
    case pulseWidthExceedsPeriod
    case enterValidFrequency
    case enterValidEnergy
    case enterValidPower
    case enterValidReadings

    var message: String {
        switch self {
        case .enterValidPositiveValues:
            return "Enter valid positive values"
        case .enterValidEnergyPerPulse:
            return "Enter valid energy per pulse"
        case .enterValidFluencePerPulse:
            return "Enter valid fluence per pulse"
        case .enterValidRepRateAndSpotSize:
            return "Enter valid Rep Rate and spot size"
        case .enterValidPulseWidth:
            return "Enter a valid pulse width"
        case .enterOffTimeOrPPS:
            return "Enter either Off-Time or PPS"
        case .enterOnlyOneOffTimeOrPPS:
            return "Enter only one: Off-Time OR PPS"
        case .pulseWidthExceedsPeriod:
            return "Pulse width exceeds period (1/PPS)"
        case .enterValidFrequency:
            return "Enter a valid frequency"
        case .enterValidEnergy:
            return "Enter a valid energy value"
        case .enterValidPower:
            return "Enter a valid power value"
        case .enterValidReadings:
            return "Enter valid readings for both fields"
        }
    }
}

enum BeamShape: Hashable, Sendable {
    case circular(diameterMM: Double)
    case square(sideMM: Double)
    case rectangle(lengthMM: Double, widthMM: Double)
}

enum EnergyUnit: String, CaseIterable, Identifiable, Sendable {
    case millijoule = "mJ"
    case joule = "J"

    var id: String { rawValue }
}

/// Local photometry math. Formulas match bundled
/// `density_calculator.html`, `fluence.html`, `duty_cycle.html`,
/// `avgpower.html`, and `wavelength.html`.
enum PhotometryMath {
    static let spotSizesMM: [Int] = Array(2...30)
    static let defaultCircularDiameterMM = 15
    static let defaultRectangularMM = 10

    /// mm² → cm² is `÷ 100`, same as the HTML (`π × (d÷2)² ÷ 100`).
    static func areaCm2(_ shape: BeamShape) -> Double {
        switch shape {
        case .circular(let diameterMM):
            let radius = diameterMM / 2
            return .pi * radius * radius / 100
        case .square(let sideMM):
            return (sideMM * sideMM) / 100
        case .rectangle(let lengthMM, let widthMM):
            return (lengthMM * widthMM) / 100
        }
    }

    static func fluenceJPerCm2(energyJ: Double, areaCm2: Double) -> Result<Double, CalculatorValidation> {
        guard energyJ > 0, areaCm2 > 0 else { return .failure(.enterValidPositiveValues) }
        return .success(energyJ / areaCm2)
    }

    static func irradianceWPerCm2(powerW: Double, areaCm2: Double) -> Result<Double, CalculatorValidation> {
        guard powerW > 0, areaCm2 > 0 else { return .failure(.enterValidPositiveValues) }
        return .success(powerW / areaCm2)
    }

    struct PulsedIrradiance: Equatable, Sendable {
        var avgIrradianceWPerCm2: Double
        var avgPowerW: Double
        var perPulseValue: Double
        var perPulseUnit: String
        var repRateHz: Double
        var areaCm2: Double
    }

    static func pulsedIrradianceFromEnergy(
        energyJ: Double,
        repRateHz: Double,
        areaCm2: Double
    ) -> Result<PulsedIrradiance, CalculatorValidation> {
        guard repRateHz > 0, areaCm2 > 0 else { return .failure(.enterValidRepRateAndSpotSize) }
        guard energyJ > 0 else { return .failure(.enterValidEnergyPerPulse) }
        let avgPower = energyJ * repRateHz
        return .success(
            PulsedIrradiance(
                avgIrradianceWPerCm2: avgPower / areaCm2,
                avgPowerW: avgPower,
                perPulseValue: energyJ,
                perPulseUnit: "J",
                repRateHz: repRateHz,
                areaCm2: areaCm2
            )
        )
    }

    static func pulsedIrradianceFromFluence(
        fluenceJPerCm2: Double,
        repRateHz: Double,
        areaCm2: Double
    ) -> Result<PulsedIrradiance, CalculatorValidation> {
        guard repRateHz > 0, areaCm2 > 0 else { return .failure(.enterValidRepRateAndSpotSize) }
        guard fluenceJPerCm2 > 0 else { return .failure(.enterValidFluencePerPulse) }
        let avgIrradiance = fluenceJPerCm2 * repRateHz
        return .success(
            PulsedIrradiance(
                avgIrradianceWPerCm2: avgIrradiance,
                avgPowerW: avgIrradiance * areaCm2,
                perPulseValue: fluenceJPerCm2,
                perPulseUnit: "J/cm²",
                repRateHz: repRateHz,
                areaCm2: areaCm2
            )
        )
    }

    struct DutyCycle: Equatable, Sendable {
        var dutyCyclePercent: Double
        var pulseWidthMS: Double
        var offTimeMS: Double
        var periodMS: Double
        var frequencyHz: Double
    }

    /// Pulse width (ms) plus exactly one of off-time (ms) or PPS (Hz).
    /// Period from PPS is `1000 / PPS` (HTML).
    static func dutyCycle(
        pulseWidthMS: Double?,
        offTimeMS: Double?,
        pulsesPerSecond: Double?
    ) -> Result<DutyCycle, CalculatorValidation> {
        guard let pulseWidthMS, pulseWidthMS > 0 else {
            return .failure(.enterValidPulseWidth)
        }
        let hasOff = offTimeMS.map { $0 > 0 } ?? false
        let hasPPS = pulsesPerSecond.map { $0 > 0 } ?? false
        if !hasOff && !hasPPS { return .failure(.enterOffTimeOrPPS) }
        if hasOff && hasPPS { return .failure(.enterOnlyOneOffTimeOrPPS) }

        if hasOff, let offTimeMS {
            let period = pulseWidthMS + offTimeMS
            return .success(
                DutyCycle(
                    dutyCyclePercent: (pulseWidthMS / period) * 100,
                    pulseWidthMS: pulseWidthMS,
                    offTimeMS: offTimeMS,
                    periodMS: period,
                    frequencyHz: 1000 / period
                )
            )
        }

        guard let pps = pulsesPerSecond else { return .failure(.enterOffTimeOrPPS) }
        let period = 1000 / pps
        let off = period - pulseWidthMS
        if off < 0 { return .failure(.pulseWidthExceedsPeriod) }
        return .success(
            DutyCycle(
                dutyCyclePercent: (pulseWidthMS / period) * 100,
                pulseWidthMS: pulseWidthMS,
                offTimeMS: off,
                periodMS: period,
                frequencyHz: pps
            )
        )
    }

    static func energyJoules(_ value: Double, unit: EnergyUnit) -> Double {
        switch unit {
        case .millijoule: return value / 1000
        case .joule: return value
        }
    }

    static func averagePowerWatts(energy: Double, unit: EnergyUnit, frequencyHz: Double) -> Result<Double, CalculatorValidation> {
        guard frequencyHz > 0 else { return .failure(.enterValidFrequency) }
        guard energy > 0 else { return .failure(.enterValidEnergy) }
        return .success(energyJoules(energy, unit: unit) * frequencyHz)
    }

    static func pulseEnergyJoules(averagePowerW: Double, frequencyHz: Double) -> Result<Double, CalculatorValidation> {
        guard frequencyHz > 0 else { return .failure(.enterValidFrequency) }
        guard averagePowerW > 0 else { return .failure(.enterValidPower) }
        return .success(averagePowerW / frequencyHz)
    }

    struct WavelengthResult: Equatable, Sendable {
        var wavelengthNM: Double
        var baseWavelengthNM: Double
        var deltaPercent: Double
        var ratioWithoutFilter: Double
        var ratioWithFilter: Double
        var correctionNM: Double
        var energyOutWithoutMJ: Double
        var hd1WithoutMJ: Double
        var energyOutWithMJ: Double
        var hd1WithMJ: Double
    }

    /// `Δ% = (E₂/HD1₂) ÷ (E₁/HD1₁) × 100`, then table lookup + filter correction.
    static func vbeamWavelength(
        energyOutWithoutMJ: Double?,
        hd1WithoutMJ: Double?,
        energyOutWithMJ: Double?,
        hd1WithMJ: Double?,
        correctionNM: Double
    ) -> Result<WavelengthResult, CalculatorValidation> {
        guard
            let e1 = energyOutWithoutMJ, e1 > 0,
            let h1 = hd1WithoutMJ, h1 > 0,
            let e2 = energyOutWithMJ, e2 > 0,
            let h2 = hd1WithMJ, h2 > 0
        else {
            return .failure(.enterValidReadings)
        }
        let t1 = e1 / h1
        let t2 = e2 / h2
        let delta = (t2 / t1) * 100
        let base = VBeamWavelengthTable.wavelengthNM(forDeltaPercent: delta)
        return .success(
            WavelengthResult(
                wavelengthNM: base + correctionNM,
                baseWavelengthNM: base,
                deltaPercent: delta,
                ratioWithoutFilter: t1,
                ratioWithFilter: t2,
                correctionNM: correctionNM,
                energyOutWithoutMJ: e1,
                hd1WithoutMJ: h1,
                energyOutWithMJ: e2,
                hd1WithMJ: h2
            )
        )
    }
}
