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
  var fullAccess: Bool { UserDefaults.standard.bool(forKey: "keyboardAccess") }
  var returnType = UIReturnKeyType(rawValue: UserDefaults.standard.integer(forKey: "keyboardReturn")) ?? .default
  var autocap = UITextAutocapitalizationType.none
  var keyType = UIKeyboardType(rawValue: UserDefaults.standard.integer(forKey: "keyboardType")) ?? .default
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
    .overlay(alignment: .bottom) {
      HStack {
        Image(systemName: "globe")
        Spacer()
        Image(systemName: "mic")
      }
      .font(.system(size: 26)).foregroundStyle((light ? Color.black : Color.white).opacity(0.85)).padding(.horizontal, 30).padding(.bottom, 14)
    }
    .ignoresSafeArea(edges: .bottom)
  }

  struct Embedded: UIViewRepresentable {
    let host: PreviewHost
    func makeUIView(context: Context) -> KeyboardView {
      let v = KeyboardView(host: host)
      host.board = v
      if UserDefaults.standard.integer(forKey: "keyboardClipboard") > 0 {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300)).jpegData(withCompressionQuality: 0.8) { c in
          UIColor.systemTeal.setFill(); c.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
          UIColor.systemOrange.setFill(); c.cgContext.fillEllipse(in: CGRect(x: 120, y: 60, width: 180, height: 180))
        }
        if UserDefaults.standard.integer(forKey: "keyboardClipboard") != 2 { v.seed(["bhai kal ka meeting shift ho gaya hai, 4 baje ke baad call karna", "https://bolkit.app/download", "Thanks for the update. I will send the invoice by Friday.", "+91 98765 43210"], image: img, images: UserDefaults.standard.integer(forKey: "keyboardClipboard") == 3) }
        v.showClips(true)
      }
      return v
    }
    func updateUIView(_ v: KeyboardView, context: Context) {}
  }
}
#endif
