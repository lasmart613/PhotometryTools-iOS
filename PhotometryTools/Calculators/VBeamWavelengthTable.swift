import Foundation

/// One row of the Candela VBeam interference-filter lookup in `wavelength.html`.
struct WavelengthTableRow: Hashable, Sendable {
    let deltaPercent: Double
    let wavelengthNM: Double
}

/// Closest-row + linear interpolation used by bundled `wavelength.html`.
enum VBeamWavelengthTable: Sendable {
    static let rows: [WavelengthTableRow] = [
        WavelengthTableRow(deltaPercent: 5.83, wavelengthNM: 586.00),
        WavelengthTableRow(deltaPercent: 5.97, wavelengthNM: 586.10),
        WavelengthTableRow(deltaPercent: 6.11, wavelengthNM: 586.20),
        WavelengthTableRow(deltaPercent: 6.25, wavelengthNM: 586.30),
        WavelengthTableRow(deltaPercent: 6.39, wavelengthNM: 586.40),
        WavelengthTableRow(deltaPercent: 6.53, wavelengthNM: 586.50),
        WavelengthTableRow(deltaPercent: 6.67, wavelengthNM: 586.60),
        WavelengthTableRow(deltaPercent: 6.81, wavelengthNM: 586.70),
        WavelengthTableRow(deltaPercent: 6.95, wavelengthNM: 586.80),
        WavelengthTableRow(deltaPercent: 7.09, wavelengthNM: 586.90),
        WavelengthTableRow(deltaPercent: 7.23, wavelengthNM: 587.00),
        WavelengthTableRow(deltaPercent: 7.47, wavelengthNM: 587.10),
        WavelengthTableRow(deltaPercent: 7.71, wavelengthNM: 587.20),
        WavelengthTableRow(deltaPercent: 7.95, wavelengthNM: 587.30),
        WavelengthTableRow(deltaPercent: 8.19, wavelengthNM: 587.40),
        WavelengthTableRow(deltaPercent: 8.44, wavelengthNM: 587.50),
        WavelengthTableRow(deltaPercent: 8.68, wavelengthNM: 587.60),
        WavelengthTableRow(deltaPercent: 8.92, wavelengthNM: 587.70),
        WavelengthTableRow(deltaPercent: 9.16, wavelengthNM: 587.80),
        WavelengthTableRow(deltaPercent: 9.40, wavelengthNM: 587.90),
        WavelengthTableRow(deltaPercent: 9.64, wavelengthNM: 588.00),
        WavelengthTableRow(deltaPercent: 9.95, wavelengthNM: 588.10),
        WavelengthTableRow(deltaPercent: 10.25, wavelengthNM: 588.20),
        WavelengthTableRow(deltaPercent: 10.55, wavelengthNM: 588.30),
        WavelengthTableRow(deltaPercent: 10.85, wavelengthNM: 588.40),
        WavelengthTableRow(deltaPercent: 11.16, wavelengthNM: 588.50),
        WavelengthTableRow(deltaPercent: 11.46, wavelengthNM: 588.60),
        WavelengthTableRow(deltaPercent: 11.76, wavelengthNM: 588.70),
        WavelengthTableRow(deltaPercent: 12.06, wavelengthNM: 588.80),
        WavelengthTableRow(deltaPercent: 12.36, wavelengthNM: 588.90),
        WavelengthTableRow(deltaPercent: 12.66, wavelengthNM: 589.00),
        WavelengthTableRow(deltaPercent: 12.93, wavelengthNM: 589.10),
        WavelengthTableRow(deltaPercent: 13.19, wavelengthNM: 589.20),
        WavelengthTableRow(deltaPercent: 13.46, wavelengthNM: 589.30),
        WavelengthTableRow(deltaPercent: 13.73, wavelengthNM: 589.40),
        WavelengthTableRow(deltaPercent: 14.00, wavelengthNM: 589.50),
        WavelengthTableRow(deltaPercent: 14.26, wavelengthNM: 589.60),
        WavelengthTableRow(deltaPercent: 14.53, wavelengthNM: 589.70),
        WavelengthTableRow(deltaPercent: 14.79, wavelengthNM: 589.80),
        WavelengthTableRow(deltaPercent: 15.06, wavelengthNM: 589.90),
        WavelengthTableRow(deltaPercent: 15.32, wavelengthNM: 590.00),
        WavelengthTableRow(deltaPercent: 15.46, wavelengthNM: 590.10),
        WavelengthTableRow(deltaPercent: 15.60, wavelengthNM: 590.20),
        WavelengthTableRow(deltaPercent: 15.74, wavelengthNM: 590.30),
        WavelengthTableRow(deltaPercent: 15.87, wavelengthNM: 590.40),
        WavelengthTableRow(deltaPercent: 16.01, wavelengthNM: 590.50),
        WavelengthTableRow(deltaPercent: 16.15, wavelengthNM: 590.60),
        WavelengthTableRow(deltaPercent: 16.29, wavelengthNM: 590.70),
        WavelengthTableRow(deltaPercent: 16.43, wavelengthNM: 590.80),
        WavelengthTableRow(deltaPercent: 16.57, wavelengthNM: 590.90),
        WavelengthTableRow(deltaPercent: 16.71, wavelengthNM: 591.00),
        WavelengthTableRow(deltaPercent: 16.82, wavelengthNM: 591.10),
        WavelengthTableRow(deltaPercent: 16.93, wavelengthNM: 591.20),
        WavelengthTableRow(deltaPercent: 17.05, wavelengthNM: 591.30),
        WavelengthTableRow(deltaPercent: 17.16, wavelengthNM: 591.40),
        WavelengthTableRow(deltaPercent: 17.27, wavelengthNM: 591.50),
        WavelengthTableRow(deltaPercent: 17.38, wavelengthNM: 591.60),
        WavelengthTableRow(deltaPercent: 17.50, wavelengthNM: 591.70),
        WavelengthTableRow(deltaPercent: 17.61, wavelengthNM: 591.80),
        WavelengthTableRow(deltaPercent: 17.72, wavelengthNM: 591.90),
        WavelengthTableRow(deltaPercent: 17.83, wavelengthNM: 592.00),
        WavelengthTableRow(deltaPercent: 18.04, wavelengthNM: 592.10),
        WavelengthTableRow(deltaPercent: 18.24, wavelengthNM: 592.20),
        WavelengthTableRow(deltaPercent: 18.45, wavelengthNM: 592.30),
        WavelengthTableRow(deltaPercent: 18.65, wavelengthNM: 592.40),
        WavelengthTableRow(deltaPercent: 18.86, wavelengthNM: 592.50),
        WavelengthTableRow(deltaPercent: 19.06, wavelengthNM: 592.60),
        WavelengthTableRow(deltaPercent: 19.27, wavelengthNM: 592.70),
        WavelengthTableRow(deltaPercent: 19.47, wavelengthNM: 592.80),
        WavelengthTableRow(deltaPercent: 19.68, wavelengthNM: 592.90),
        WavelengthTableRow(deltaPercent: 19.89, wavelengthNM: 593.00),
        WavelengthTableRow(deltaPercent: 20.24, wavelengthNM: 593.10),
        WavelengthTableRow(deltaPercent: 20.59, wavelengthNM: 593.20),
        WavelengthTableRow(deltaPercent: 20.95, wavelengthNM: 593.30),
        WavelengthTableRow(deltaPercent: 21.30, wavelengthNM: 593.40),
        WavelengthTableRow(deltaPercent: 21.66, wavelengthNM: 593.50),
        WavelengthTableRow(deltaPercent: 22.01, wavelengthNM: 593.60),
        WavelengthTableRow(deltaPercent: 22.37, wavelengthNM: 593.70),
        WavelengthTableRow(deltaPercent: 22.72, wavelengthNM: 593.80),
        WavelengthTableRow(deltaPercent: 23.08, wavelengthNM: 593.90),
        WavelengthTableRow(deltaPercent: 23.43, wavelengthNM: 594.00),
        WavelengthTableRow(deltaPercent: 23.91, wavelengthNM: 594.10),
        WavelengthTableRow(deltaPercent: 24.38, wavelengthNM: 594.20),
        WavelengthTableRow(deltaPercent: 24.86, wavelengthNM: 594.30),
        WavelengthTableRow(deltaPercent: 25.33, wavelengthNM: 594.40),
        WavelengthTableRow(deltaPercent: 25.81, wavelengthNM: 594.50),
        WavelengthTableRow(deltaPercent: 26.28, wavelengthNM: 594.60),
        WavelengthTableRow(deltaPercent: 26.76, wavelengthNM: 594.70),
        WavelengthTableRow(deltaPercent: 27.24, wavelengthNM: 594.80),
        WavelengthTableRow(deltaPercent: 27.72, wavelengthNM: 594.90),
        WavelengthTableRow(deltaPercent: 28.19, wavelengthNM: 595.00),
        WavelengthTableRow(deltaPercent: 28.78, wavelengthNM: 595.10),
        WavelengthTableRow(deltaPercent: 29.36, wavelengthNM: 595.20),
        WavelengthTableRow(deltaPercent: 29.95, wavelengthNM: 595.30),
        WavelengthTableRow(deltaPercent: 30.53, wavelengthNM: 595.40),
        WavelengthTableRow(deltaPercent: 31.12, wavelengthNM: 595.50),
        WavelengthTableRow(deltaPercent: 31.70, wavelengthNM: 595.60),
        WavelengthTableRow(deltaPercent: 32.29, wavelengthNM: 595.70),
        WavelengthTableRow(deltaPercent: 32.87, wavelengthNM: 595.80),
        WavelengthTableRow(deltaPercent: 33.46, wavelengthNM: 595.90),
        WavelengthTableRow(deltaPercent: 34.04, wavelengthNM: 596.00),
        WavelengthTableRow(deltaPercent: 34.61, wavelengthNM: 596.10),
        WavelengthTableRow(deltaPercent: 35.18, wavelengthNM: 596.20),
        WavelengthTableRow(deltaPercent: 35.76, wavelengthNM: 596.30),
        WavelengthTableRow(deltaPercent: 36.33, wavelengthNM: 596.40),
        WavelengthTableRow(deltaPercent: 36.91, wavelengthNM: 596.50),
        WavelengthTableRow(deltaPercent: 37.48, wavelengthNM: 596.60),
        WavelengthTableRow(deltaPercent: 38.05, wavelengthNM: 596.70),
        WavelengthTableRow(deltaPercent: 38.62, wavelengthNM: 596.80),
        WavelengthTableRow(deltaPercent: 39.20, wavelengthNM: 596.90),
        WavelengthTableRow(deltaPercent: 39.77, wavelengthNM: 597.00),
        WavelengthTableRow(deltaPercent: 40.21, wavelengthNM: 597.10),
        WavelengthTableRow(deltaPercent: 40.65, wavelengthNM: 597.20),
        WavelengthTableRow(deltaPercent: 41.10, wavelengthNM: 597.30),
        WavelengthTableRow(deltaPercent: 41.54, wavelengthNM: 597.40),
        WavelengthTableRow(deltaPercent: 41.98, wavelengthNM: 597.50),
        WavelengthTableRow(deltaPercent: 42.42, wavelengthNM: 597.60),
        WavelengthTableRow(deltaPercent: 42.86, wavelengthNM: 597.70),
        WavelengthTableRow(deltaPercent: 43.30, wavelengthNM: 597.80),
        WavelengthTableRow(deltaPercent: 43.75, wavelengthNM: 597.90),
        WavelengthTableRow(deltaPercent: 44.19, wavelengthNM: 598.00),
        WavelengthTableRow(deltaPercent: 44.53, wavelengthNM: 598.10),
        WavelengthTableRow(deltaPercent: 44.87, wavelengthNM: 598.20),
        WavelengthTableRow(deltaPercent: 45.22, wavelengthNM: 598.30),
        WavelengthTableRow(deltaPercent: 45.56, wavelengthNM: 598.40),
        WavelengthTableRow(deltaPercent: 45.90, wavelengthNM: 598.50),
        WavelengthTableRow(deltaPercent: 46.24, wavelengthNM: 598.60),
        WavelengthTableRow(deltaPercent: 46.58, wavelengthNM: 598.70),
        WavelengthTableRow(deltaPercent: 46.92, wavelengthNM: 598.80),
        WavelengthTableRow(deltaPercent: 47.27, wavelengthNM: 598.90),
        WavelengthTableRow(deltaPercent: 47.61, wavelengthNM: 599.00),
        WavelengthTableRow(deltaPercent: 47.95, wavelengthNM: 599.10),
        WavelengthTableRow(deltaPercent: 48.28, wavelengthNM: 599.20),
        WavelengthTableRow(deltaPercent: 48.61, wavelengthNM: 599.30),
        WavelengthTableRow(deltaPercent: 48.94, wavelengthNM: 599.40),
        WavelengthTableRow(deltaPercent: 49.28, wavelengthNM: 599.50),
        WavelengthTableRow(deltaPercent: 49.61, wavelengthNM: 599.60),
        WavelengthTableRow(deltaPercent: 49.95, wavelengthNM: 599.70),
        WavelengthTableRow(deltaPercent: 50.28, wavelengthNM: 599.80),
        WavelengthTableRow(deltaPercent: 50.62, wavelengthNM: 599.90),
        WavelengthTableRow(deltaPercent: 50.95, wavelengthNM: 600.00)
    ]

    /// Matches `lookupWavelength(d)` in `wavelength.html`: interpolate when `d`
    /// sits between two table deltas; otherwise use the closest row.
    static func wavelengthNM(forDeltaPercent d: Double) -> Double {
        guard let first = rows.first else { return .nan }
        var closest = first
        var minDiff = abs(d - first.deltaPercent)
        for row in rows.dropFirst() {
            let diff = abs(d - row.deltaPercent)
            if diff < minDiff {
                minDiff = diff
                closest = row
            }
        }
        for i in 0..<(rows.count - 1) {
            let a = rows[i]
            let b = rows[i + 1]
            if d >= a.deltaPercent && d <= b.deltaPercent {
                let span = b.deltaPercent - a.deltaPercent
                if span == 0 { return a.wavelengthNM }
                return a.wavelengthNM + (b.wavelengthNM - a.wavelengthNM) * (d - a.deltaPercent) / span
            }
        }
        return closest.wavelengthNM
    }
}
