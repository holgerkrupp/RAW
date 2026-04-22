import Foundation

struct SensorValue: Identifiable {
    let id = UUID()
    let name: String
    let value: String
}
