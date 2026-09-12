import SwiftUI

struct CalculatorItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
}

/// Native stub hub for P0 photometry calculators.
/// Implementations land in a later increment; this list matches the Android inventory.
struct CalculatorsView: View {
    private let items: [CalculatorItem] = [
        CalculatorItem(
            id: "density",
            title: "Density",
            subtitle: "Unified fluence (J/cm²) and irradiance (W/cm²)",
            systemImage: "square.grid.3x3"
        ),
        CalculatorItem(
            id: "wavelength",
            title: "Wavelength",
            subtitle: "Candela VBeam wavelength and filter table",
            systemImage: "waveform"
        ),
        CalculatorItem(
            id: "duty-cycle",
            title: "Duty Cycle",
            subtitle: "Pulsed laser duty cycle",
            systemImage: "metronome"
        ),
        CalculatorItem(
            id: "avg-power",
            title: "Average Power",
            subtitle: "Energy × repetition frequency",
            systemImage: "bolt"
        ),
    ]

    var body: some View {
        NavigationStack {
            List(items) { item in
                NavigationLink(value: item) {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.headline)
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: item.systemImage)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Calculators")
            .navigationDestination(for: CalculatorItem.self) { item in
                CalculatorStubView(item: item)
            }
        }
    }
}

#Preview {
    CalculatorsView()
}
