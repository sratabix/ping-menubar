import SwiftUI

public struct PingApp: App {
    @StateObject private var model = AppModel()

    public init() {}

    public var body: some Scene {
        MenuBarExtra {
            ContentView().environmentObject(model)
        } label: {
            Image(nsImage: model.label)
        }
        .menuBarExtraStyle(.window)
    }
}
