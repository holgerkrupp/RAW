import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var sensorStore: SensorStore

    var body: some View {
        NavigationSplitView {
            List(SensorStore.SensorSection.allCases, selection: $sensorStore.selectedSection) { section in
                Label(section.rawValue, systemImage: icon(for: section))
                    .padding(.vertical, 4)
            }
            .navigationTitle("Liquid Glass Sensors")
            .scrollContentBackground(.hidden)
            .background(.ultraThinMaterial)
        } detail: {
            if let section = sensorStore.selectedSection {
                SensorDetailView(title: section.rawValue, values: sensorStore.values(for: section))
            } else {
                ContentUnavailableView("Select a sensor section", systemImage: "sensor.tag.radiowaves.forward")
            }
        }
    }

    private func icon(for section: SensorStore.SensorSection) -> String {
        switch section {
        case .location: return "location"
        case .motion: return "move.3d"
        case .barometer: return "gauge.with.dots.needle.33percent"
        case .magnetometer: return "location.north.line"
        case .radio: return "antenna.radiowaves.left.and.right"
        case .device: return "cpu"
        }
    }
}

struct SensorDetailView: View {
    let title: String
    let values: [SensorValue]

    var body: some View {
        List(values) { sensor in
            VStack(alignment: .leading, spacing: 6) {
                Text(sensor.name)
                    .font(.headline)
                Text(sensor.value)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(
            LinearGradient(colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        )
        .navigationTitle(title)
    }
}
