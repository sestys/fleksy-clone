import SwiftUI

struct ContentView: View {
    @State private var text = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("A personal rebuild of the Fleksy keyboard: flat colourful keys, gesture editing, Czech + English.")
                        .foregroundStyle(.secondary)

                    GroupBox("Try it") {
                        TextField("Tap here and switch to Fleksy Clone with the globe key", text: $text, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)
                            .accessibilityIdentifier("testField")
                        HStack {
                            Text(text.isEmpty ? " " : text)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("mirror")
                            Spacer()
                            Button("Clear") { text = "" }
                                .accessibilityIdentifier("clearButton")
                        }
                    }

                    GroupBox("Enable the keyboard") {
                        VStack(alignment: .leading, spacing: 8) {
                            step(1, "Open Settings › General › Keyboard › Keyboards")
                            step(2, "Tap Add New Keyboard… and pick Fleksy Clone")
                            step(3, "In any text field, hold the 🌐 key and choose Fleksy Clone")
                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Label("Open Settings", systemImage: "gear")
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                        }
                    }

                    GroupBox("Gestures") {
                        VStack(alignment: .leading, spacing: 6) {
                            gesture("→", "Swipe right: space. Twice: period.")
                            gesture("←", "Swipe left: delete the last word")
                            gesture("↑", "Swipe up: next correction for the last word")
                            gesture("↓", "Swipe down: previous correction / what you typed")
                            gesture("⇄", "Swipe the space bar (or two fingers): switch Čeština / English")
                            gesture("⇊", "Two-finger swipe down: hide keyboard")
                            gesture("⌛︎", "Hold a letter: accents (ě š č ř ž ý á í é ú ů)")
                            gesture("⚙︎", "Tap the dot at the left of the suggestion bar: themes and settings")
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Fleksy Clone")
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").bold().frame(width: 20)
            Text(text)
        }
    }

    private func gesture(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(symbol).font(.title3).frame(width: 28)
            Text(text).font(.callout)
        }
    }
}

#Preview {
    ContentView()
}
