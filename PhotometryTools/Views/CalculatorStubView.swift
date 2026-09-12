import SwiftUI

struct CalculatorStubView: View {
    let item: CalculatorItem

    var body: some View {
        ContentUnavailableView {
            Label(item.title, systemImage: item.systemImage)
        } description: {
            Text("Native \(item.title.lowercased()) calculator is a stub. P0 parity will implement the Android math from the HTML calculators.")
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        CalculatorStubView(
            item: CalculatorItem(
                id: "density",
                title: "Density",
                subtitle: "Unified fluence and irradiance",
                systemImage: "square.grid.3x3"
            )
        )
    }
}
