import SwiftUI

@main
struct RAWApp: App {
    @StateObject private var sensorStore = SensorStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sensorStore)
                .task {
                    sensorStore.start()
                }
        }
    }
}
