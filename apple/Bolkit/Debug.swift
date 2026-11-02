#if DEBUG
import SwiftUI

struct KeyboardReference: View {
  @State private var text = ""
  @FocusState private var focus: Bool
  let light = UserDefaults.standard.bool(forKey: "keyboardLight")
  var body: some View {
    VStack {
      TextField("Reference", text: $text).focused($focus).textFieldStyle(.roundedBorder).padding()
      Spacer()
    }
    .background((light ? Color.white : Color.black).ignoresSafeArea())
    .preferredColorScheme(light ? .light : .dark)
    .onAppear { focus = true }
  }
}

@MainActor @Observable
final class PreviewHost: KeyboardHost {
  var text = ""
  var state = MicState.ready
  var board: KeyboardView?
  var before: String { text }
  var returnType = UIReturnKeyType.default
  var autocap = UITextAutocapitalizationType.none
  var appearance = UserDefaults.standard.bool(forKey: "keyboardLight") ? UIKeyboardAppearance.light : .default
  func insert(_ s: String) { text += s }
  func delete() { if !text.isEmpty { text.removeLast() } }
  func move(_ n: Int) {}
  func mic() {
    state = state == .ready ? .listening : .ready
    board?.setMic(state)
    board?.setStatus(state == .listening ? "Listening. Tap the mic when done" : nil)
  }
}

struct KeyboardPreview: View {
  @State private var host = PreviewHost()
  let light = UserDefaults.standard.bool(forKey: "keyboardLight")
  var body: some View {
    VStack {
      Text(host.text.isEmpty ? "Preview" : host.text).foregroundStyle(.gray).frame(maxWidth: .infinity, alignment: .leading).padding()
      Spacer()
      Embedded(host: host).frame(height: KeyboardView.height).padding(.bottom, UserDefaults.standard.double(forKey: "keyboardLift"))
    }
    .background((light ? Color.white : Color.black).ignoresSafeArea())
    .preferredColorScheme(light ? .light : .dark)
    .ignoresSafeArea(edges: .bottom)
  }

  struct Embedded: UIViewRepresentable {
    let host: PreviewHost
    func makeUIView(context: Context) -> KeyboardView {
      let v = KeyboardView(host: host, solidBackground: true)
      host.board = v
      return v
    }
    func updateUIView(_ v: KeyboardView, context: Context) {}
  }
}
#endif
