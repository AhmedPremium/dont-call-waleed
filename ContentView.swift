import SwiftUI
struct ContentView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> GameController { GameController() }
    func updateUIViewController(_ controller: GameController, context: Context) {}
}
