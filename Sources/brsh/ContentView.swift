import SwiftUI

struct ContentView: View {
    var body: some View {
        HStack {
            Image(systemName: "leaf.fill")
            Text("brsh")
        }.foregroundStyle(.green)

        NavigationStack {
            List {
                NavigationLink("Mods") { ModScreen() }
                NavigationLink("FastFlags") { SettingsScreen() }
            }
            .navigationTitle("Home")
        }
    }
}
