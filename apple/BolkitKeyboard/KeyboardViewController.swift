import UIKit

class KeyboardViewController: UIInputViewController, KeyboardHost {
  private var board: KeyboardView!
  private var lastInserted = UserDefaults.standard.string(forKey: "lastResult") ?? ""
  private var visible = false
  private var height: NSLayoutConstraint!

  var before: String { textDocumentProxy.documentContextBeforeInput ?? "" }
  var returnType: UIReturnKeyType { textDocumentProxy.returnKeyType ?? .default }
  var autocap: UITextAutocapitalizationType { textDocumentProxy.autocapitalizationType ?? .sentences }
  var needsGlobe: Bool { needsInputModeSwitchKey }
  func globe() { advanceToNextInputMode() }
  var secure: Bool { textDocumentProxy.isSecureTextEntry ?? false }
  var autocorrect: UITextAutocorrectionType { textDocumentProxy.autocorrectionType ?? .default }
  var keyType: UIKeyboardType { textDocumentProxy.keyboardType ?? .default }
  var appearance: UIKeyboardAppearance { textDocumentProxy.keyboardAppearance ?? .default }

  override func loadView() {
    board = KeyboardView(host: self)
    view = board
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    height = view.heightAnchor.constraint(equalToConstant: KeyboardView.height)
    height.priority = .required - 1
    height.isActive = true
    board.onHeight = { [weak self] h in
      guard let self else { return }
      UIView.animate(withDuration: 0.25) {
        self.height.constant = h
        self.view.superview?.layoutIfNeeded()
      }
    }
    FlowShared.observe(FlowShared.changed) { [weak self] in self?.refresh() }
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    visible = true
    board.rebuild()
    refresh()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    visible = false
  }

  override func textDidChange(_ textInput: UITextInput?) { board.contextChanged() }

  override func traitCollectionDidChange(_ previous: UITraitCollection?) {
    super.traitCollectionDidChange(previous)
    board.contextChanged()
  }

  var fullAccess: Bool { hasFullAccess }

  func insert(_ s: String) { textDocumentProxy.insertText(s) }
  func delete() { textDocumentProxy.deleteBackward() }
  func move(_ n: Int) { textDocumentProxy.adjustTextPosition(byCharacterOffset: n) }

  func mic() {
    guard hasFullAccess else { board.setStatus("Turn on Allow Full Access for Bolkit KB in Settings"); return }
    let s = FlowShared.read()
    if s.alive {
      if s.phase == .idle || s.phase == .listening { FlowShared.send(s.phase == .idle ? "start" : "stop") }
    } else {
      board.setStatus("Opening Bolkit. Swipe back to keep typing")
      openApp(URL(string: "scribe://flow")!)
    }
  }

  private func refresh() {
    guard hasFullAccess else { return }
    let s = FlowShared.read()
    guard visible else { return }
    let phase = s.alive ? s.phase : .off
    if phase == .idle || phase == .off, !s.resultID.isEmpty, s.resultID != lastInserted, -s.resultAt.timeIntervalSinceNow < 20 {
      lastInserted = s.resultID
      UserDefaults.standard.set(lastInserted, forKey: "lastResult")
      if !s.resultText.isEmpty {
        insert(s.resultText)
        board.setMic(.done)
        board.setStatus("Inserted")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.refresh() }
        return
      }
    }
    board.setMic(phase == .listening ? .listening : phase == .working ? .working : .ready)
    switch phase {
    case .listening: board.setStatus(s.partial.isEmpty ? "Listening. Tap the mic when done" : String(s.partial.suffix(70)))
    case .working: board.setStatus("Writing")
    case .idle: board.setStatus(s.error ?? (-s.resultAt.timeIntervalSinceNow < 1.5 && s.resultText.isEmpty ? "Heard nothing" : nil))
    default: board.setStatus(s.error)
    }
  }

  private func openApp(_ url: URL) {
    typealias Open = @convention(c) (AnyObject, Selector, URL, [UIApplication.OpenExternalURLOptionsKey: Any], ((Bool) -> Void)?) -> Void
    let modern = sel_registerName("openURL:options:completionHandler:")
    let legacy = sel_registerName("openURL:")
    var r: UIResponder? = self
    while let x = r {
      if x.responds(to: modern), let m = class_getMethodImplementation(type(of: x), modern) {
        unsafeBitCast(m, to: Open.self)(x, modern, url, [:], nil)
        return
      }
      if x.responds(to: legacy) { _ = x.perform(legacy, with: url); return }
      r = x.next
    }
  }
}
