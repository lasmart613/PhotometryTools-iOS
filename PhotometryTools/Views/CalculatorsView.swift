import SwiftUI

struct CalculatorItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
}

/// Native photometry calculator hub. HTML copies stay available from the TSP
/// Home WebView (`calculators_menu.html` and the individual pages).
struct CalculatorsView: View {
    private let items: [CalculatorItem] = [
        CalculatorItem(
            id: "fluence",
            title: "Fluence",
            subtitle: "Energy density (J/cm²) — QA / Android Fluence path",
            systemImage: "bolt.fill"
        ),
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
            List {
                Section {
                    ForEach(items) { item in
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
                } footer: {
                    Text("Native forms. Bundled HTML calculators stay available from Home (TSP shell).")
                }
            }
            .navigationTitle("Calculators")
            .navigationDestination(for: CalculatorItem.self) { item in
                destination(for: item)
            }
        }
    }

    @ViewBuilder
    private func destination(for item: CalculatorItem) -> some View {
        switch item.id {
        case "fluence":
            DensityCalculatorView(initialMode: .fluence, title: "Fluence")
        case "density":
            DensityCalculatorView(initialMode: .fluence, title: "Density")
        case "wavelength":
            WavelengthCalculatorView()
        case "duty-cycle":
            DutyCycleCalculatorView()
        case "avg-power":
            AveragePowerCalculatorView()
        default:
            DensityCalculatorView(initialMode: .fluence)
        }
    }
}

#Preview {
    CalculatorsView()
}
