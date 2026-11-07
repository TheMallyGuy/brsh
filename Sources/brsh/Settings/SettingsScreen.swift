import SwiftUI

struct SettingsScreen: View {
    @AppStorage("notificationsOn") private var notificationsOn = true
    @AppStorage("darkMode") private var darkMode = false
    @AppStorage("username") private var username = ""
    @AppStorage("theme") private var theme = "System"
    @AppStorage("fontSize") private var fontSize = 16.0
    @AppStorage("reminderCount") private var reminderCount = 3

    @State private var showResetAlert = false

    let themes = ["System", "Light", "Dark"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Username", text: $username)
                    NavigationLink("Privacy") { PrivacyScreen() }
                }

                Section {
                    Toggle("Notifications", isOn: $notificationsOn)

                    if notificationsOn {
                        Stepper("Reminders: \(reminderCount)",
                                value: $reminderCount, in: 1...10)
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("We'll remind you about unfinished tasks.")
                }

                Section("Appearance") {
                    Picker("Theme", selection: $theme) {
                        ForEach(themes, id: \.self) { Text($0) }
                    }

                    VStack(alignment: .leading) {
                        Text("Font size: \(Int(fontSize))")
                        Slider(value: $fontSize, in: 12...24, step: 1)
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    Link("Website", destination: URL(string: "https://example.com")!)
                }

                Section {
                    Button("Reset All Settings", role: .destructive) {
                        showResetAlert = true
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Reset settings?", isPresented: $showResetAlert) {
                Button("Reset", role: .destructive) { resetAll() }
                Button("Cancel", role: .cancel) { }
            }
        }
    }

    func resetAll() {
        notificationsOn = true
        darkMode = false
        username = ""
        theme = "System"
        fontSize = 16
        reminderCount = 3
    }
}

struct PrivacyScreen: View {
    @AppStorage("analytics") private var analytics = false

    var body: some View {
        Form {
            Toggle("Share Analytics", isOn: $analytics)
        }
        .navigationTitle("Privacy")
    }
}