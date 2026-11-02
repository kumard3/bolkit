import UIKit

@MainActor protocol KeyboardHost: AnyObject {
  var before: String { get }
  var returnType: UIReturnKeyType { get }
  var autocap: UITextAutocapitalizationType { get }
  var appearance: UIKeyboardAppearance { get }
  func insert(_ s: String)
  func delete()
  func move(_ n: Int)
  func mic()
}

enum MicState { case ready, listening, working }

enum Layer { case letters, numbers, symbols }

enum KeyKind: Equatable {
  case char(String), shift, delete, layer(Layer), mic, space, ret
}

final class KeyView: UIView {
  let kind: KeyKind
  let label = UILabel()
  let icon = UIImageView()
  let lang = UILabel()
  var plain: Bool { if case .char = kind { return true }; return kind == .space }

  init(_ kind: KeyKind) {
    self.kind = kind
    super.init(frame: .zero)
    layer.cornerRadius = 8
    layer.cornerCurve = .continuous
    isUserInteractionEnabled = false
    label.textAlignment = .center
    label.adjustsFontSizeToFitWidth = true
    icon.contentMode = .center
    addSubview(label)
    addSubview(icon)
    if kind == .space {
      lang.text = "EN"
      lang.font = .systemFont(ofSize: 11, weight: .medium)
      lang.textAlignment = .right
      addSubview(lang)
    }
  }

  required init?(coder: NSCoder) { fatalError() }

  override func layoutSubviews() {
    super.layoutSubviews()
    label.frame = plain ? bounds.offsetBy(dx: 0, dy: -2) : bounds
    icon.frame = bounds
    lang.frame = CGRect(x: 0, y: bounds.height - 18, width: bounds.width - 10, height: 14)
  }
}

final class KeyboardView: UIInputView, UIInputViewAudioFeedback {
  var enableInputClicksWhenVisible: Bool { true }

  static let barHeight: CGFloat = 46
  static let height: CGFloat = barHeight + 6 + 3 * 54 + 43 + 6
  let side: CGFloat = 6.7, gap: CGFloat = 6.3, rowGap: CGFloat = 11, keyHeight: CGFloat = 43, top: CGFloat = 6

  weak var host: KeyboardHost?
  private var layer_ = Layer.letters
  private enum Shift { case off, on, lock }
  private var shift = Shift.off
  private var lastShiftTap = Date.distantPast
  private var lastSpace = Date.distantPast
  private var keys: [[KeyView]] = []
  private var micState = MicState.ready
  private var status: String?
  private let bar = SuggestionBar()
  private let popup = CAShapeLayer()
  private let popupText = UILabel()
  private var active: [UITouch: KeyView] = [:]
  private var spaceStart: [UITouch: CGFloat] = [:]
  private var spaceMoved: Set<UITouch> = []
  private var repeater: Task<Void, Never>?
  private let haptic = UIImpactFeedbackGenerator(style: .light)
  private let checker = UITextChecker()
  private var history: [String] = []
  private let solid: Bool

  init(host: KeyboardHost?, solidBackground: Bool = false) {
    self.host = host
    solid = solidBackground
    super.init(frame: .zero, inputViewStyle: .keyboard)
    isMultipleTouchEnabled = true
    addSubview(bar)
    bar.pick = { [weak self] w in self?.accept(w) }
    popup.shadowOpacity = 0.3
    popup.shadowRadius = 4
    popup.shadowOffset = CGSize(width: 0, height: 1)
    popup.isHidden = true
    layer.addSublayer(popup)
    popupText.textAlignment = .center
    popupText.font = .systemFont(ofSize: 38)
    popupText.isHidden = true
    addSubview(popupText)
    history = FlowShared.words()
    build()
    refreshShift()
    bar.show(suggestions(), status: nil)
    haptic.prepare()
  }

  required init?(coder: NSCoder) { fatalError() }

  var dark: Bool {
    switch host?.appearance ?? .default {
    case .dark: true
    case .light: false
    default: traitCollection.userInterfaceStyle == .dark
    }
  }

  private var palette: (key: UIColor, special: UIColor, text: UIColor, popup: UIColor) {
    dark
      ? (UIColor(white: 0.267, alpha: 1), UIColor(white: 0.267, alpha: 1), .white, UIColor(white: 0.267, alpha: 1))
      : (.white, .white, .black, .white)
  }

  func setStatus(_ s: String?) {
    status = s
    bar.show(s == nil ? suggestions() : [], status: s)
  }

  func setMic(_ s: MicState) {
    micState = s
    style()
  }

  func contextChanged() {
    refreshShift()
    if status == nil { bar.show(suggestions(), status: nil) }
  }

  private func rows() -> [[KeyKind]] {
    let bottom: [KeyKind] = [.layer(layer_ == .letters ? .numbers : .letters), .mic, .space, .ret]
    func chars(_ s: String) -> [KeyKind] { s.map { .char(String($0)) } }
    switch layer_ {
    case .letters:
      return [chars("qwertyuiop"), chars("asdfghjkl"), [.shift] + chars("zxcvbnm") + [.delete], bottom]
    case .numbers:
      return [chars("1234567890"), chars("-/:;()$&@\""), [.layer(.symbols)] + chars(".,?!'") + [.delete], bottom]
    case .symbols:
      return [chars("[]{}#%^*+="), chars("_\\|~<>€£¥•"), [.layer(.numbers)] + chars(".,?!'") + [.delete], bottom]
    }
  }

  private func build() {
    keys.flatMap { $0 }.forEach { $0.removeFromSuperview() }
    keys = rows().map { $0.map { KeyView($0) } }
    keys.flatMap { $0 }.forEach { insertSubview($0, belowSubview: popupText) }
    style()
    setNeedsLayout()
  }

  private func style() {
    let p = palette
    backgroundColor = !solid ? nil : (dark ? UIColor(white: 0.125, alpha: 1) : UIColor(red: 0.886, green: 0.894, blue: 0.91, alpha: 1))
    bar.apply(text: p.text, dark: dark)
    popup.fillColor = p.popup.cgColor
    popupText.textColor = p.text
    let ret = host?.returnType ?? .default
    for row in keys {
      for k in row {
        var fill = k.plain ? p.key : p.special
        var tint = p.text
        var title: String?
        var symbol: String?
        var size: CGFloat = 18
        switch k.kind {
        case .char(let c): title = shift == .off ? c : c.uppercased(); size = 27
        case .space: title = nil
        case .shift:
          symbol = shift == .lock ? "capslock.fill" : shift == .on ? "shift.fill" : "shift"
          if shift != .off { fill = dark ? UIColor(white: 0.95, alpha: 1) : .white; tint = .black }
        case .delete: symbol = "delete.left"
        case .layer(let l): title = l == .letters ? "ABC" : l == .numbers ? "123" : "#+="
        case .mic:
          symbol = micState == .listening ? "waveform" : "mic.fill"
          if micState == .listening { fill = .systemRed; tint = .white }
          if micState == .working { tint = tint.withAlphaComponent(0.4) }
        case .ret:
          if let t = Self.returnTitle(ret) { title = t } else { symbol = "return" }
          if Self.accent(ret) { fill = .systemBlue; tint = .white }
        }
        k.backgroundColor = fill
        k.label.text = title
        k.label.textColor = tint
        k.label.font = .systemFont(ofSize: size, weight: .regular)
        k.icon.tintColor = tint
        k.lang.textColor = tint.withAlphaComponent(0.5)
        k.icon.image = symbol.flatMap { UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .regular)) }
      }
    }
  }

  static func returnTitle(_ t: UIReturnKeyType) -> String? {
    switch t {
    case .go: "go"
    case .google, .search, .yahoo: "search"
    case .send: "send"
    case .next: "next"
    case .done: "done"
    case .join: "join"
    case .route: "route"
    case .continue: "continue"
    case .emergencyCall: "Emergency"
    default: nil
    }
  }

  static func accent(_ t: UIReturnKeyType) -> Bool { [.go, .google, .search, .yahoo, .send, .done, .join, .route, .continue].contains(t) }

  override func layoutSubviews() {
    super.layoutSubviews()
    bar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Self.barHeight)
    let w = bounds.width
    let kw = (w - 2 * side - 9 * gap) / 10
    let wide = (w - 2 * side - 7 * kw - 6 * gap) / 2 - 13.7
    for (r, row) in keys.enumerated() {
      let y = Self.barHeight + top + CGFloat(r) * (keyHeight + rowGap)
      switch r {
      case 0: place(row, y: y, x: side, widths: row.map { _ in kw })
      case 1 where layer_ == .letters:
        place(row, y: y, x: side + (kw + gap) / 2, widths: row.map { _ in kw })
      case 1: place(row, y: y, x: side, widths: row.map { _ in kw })
      case 2:
        let n = CGFloat(row.count - 2)
        let mid = layer_ == .letters ? kw : (w - 2 * side - 2 * wide - 2 * 13.7 - (n - 1) * gap) / n
        let span = wide * 2 + 27.4 + n * mid + (n - 1) * gap
        place(row, y: y, x: (w - span) / 2, widths: [wide] + row.dropFirst().dropLast().map { _ in mid } + [wide], gaps: [13.7] + Array(repeating: gap, count: row.count - 3) + [13.7])
      default:
        let unit = kw * 1.3
        let ret = kw * 2.8
        place(row, y: y, x: side, widths: [unit, unit, w - 2 * side - unit * 2 - ret - 3 * gap, ret])
      }
    }
  }

  private func place(_ row: [KeyView], y: CGFloat, x: CGFloat, widths: [CGFloat], gaps: [CGFloat]? = nil) {
    var x = x
    for (i, k) in row.enumerated() {
      k.frame = CGRect(x: x, y: y, width: widths[i], height: keyHeight)
      x += widths[i] + (i < row.count - 1 ? (gaps?[i] ?? gap) : 0)
    }
  }

  private func key(at p: CGPoint) -> KeyView? {
    let all = keys.flatMap { $0 }
    if let k = all.first(where: { $0.frame.insetBy(dx: -gap / 2, dy: -rowGap / 2).contains(p) }) { return k }
    guard p.y > Self.barHeight else { return nil }
    return all.min { dist($0.frame, p) < dist($1.frame, p) }
  }

  private func dist(_ r: CGRect, _ p: CGPoint) -> CGFloat {
    let dx = max(r.minX - p.x, 0, p.x - r.maxX), dy = max(r.minY - p.y, 0, p.y - r.maxY)
    return dx * dx + dy * dy
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    for t in touches {
      let p = t.location(in: self)
      guard p.y > Self.barHeight - 8, let k = key(at: p) else { continue }
      press(k, t)
      if k.kind == .space { spaceStart[t] = p.x }
    }
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    for t in touches {
      let p = t.location(in: self)
      if let x0 = spaceStart[t], active[t]?.kind == .space {
        if spaceMoved.contains(t) || abs(p.x - x0) > 12 {
          spaceMoved.insert(t)
          let steps = Int((p.x - x0) / 9)
          if steps != 0 { host?.move(steps); spaceStart[t] = x0 + CGFloat(steps) * 9; tick() }
        }
        continue
      }
      guard let old = active[t], case .char = old.kind, let k = key(at: p), k !== old else { continue }
      release(old)
      active[t] = nil
      press(k, t, sound: false)
    }
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    for t in touches {
      guard let k = active[t] else { continue }
      let moved = spaceMoved.contains(t)
      active[t] = nil
      spaceStart[t] = nil
      spaceMoved.remove(t)
      release(k)
      if !moved { commit(k) }
    }
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    for t in touches {
      if let k = active[t] { release(k) }
      active[t] = nil
      spaceStart[t] = nil
      spaceMoved.remove(t)
    }
    repeater?.cancel()
  }

  private func tick() {
    UIDevice.current.playInputClick()
    haptic.impactOccurred(intensity: 0.5)
  }

  private func press(_ k: KeyView, _ t: UITouch, sound: Bool = true) {
    active[t] = k
    if sound { tick() }
    if case .char(let c) = k.kind {
      k.backgroundColor = palette.key.withAlphaComponent(0.6)
      showPopup(k, c)
    } else if k.kind == .delete {
      host?.delete()
      refreshShiftSoon()
      repeater?.cancel()
      repeater = Task { @MainActor [weak self] in
        try? await Task.sleep(for: .milliseconds(450))
        var n = 0
        while !Task.isCancelled, let self {
          if n > 14, let b = self.host?.before, !b.isEmpty {
            var rest = Substring(b)
            while rest.last == " " { rest.removeLast() }
            while let c = rest.last, c != " ", c != "\n" { rest.removeLast() }
            let count = b.count - rest.count
            for _ in 0..<max(count, 1) { self.host?.delete() }
          } else { self.host?.delete() }
          self.tick()
          n += 1
          try? await Task.sleep(for: .milliseconds(max(35, 110 - n * 6)))
        }
      }
    } else if k.kind != .space {
      k.alpha = 0.75
    }
  }

  private func release(_ k: KeyView) {
    hidePopup()
    if k.kind == .delete { repeater?.cancel(); refreshShiftSoon() }
    k.alpha = 1
    if case .char = k.kind { k.backgroundColor = palette.key }
  }

  private func commit(_ k: KeyView) {
    guard let host else { return }
    switch k.kind {
    case .char(let c):
      host.insert(shift == .off ? c : c.uppercased())
      if shift == .on { shift = .off; style() }
      refreshShiftSoon()
    case .space:
      let b = host.before
      if -lastSpace.timeIntervalSinceNow < 0.6, b.hasSuffix(" "), let p = b.dropLast().last, p.isLetter || p.isNumber {
        host.delete()
        host.insert(". ")
      } else { host.insert(" ") }
      lastSpace = Date()
      if layer_ != .letters { switchLayer(.letters) }
      refreshShiftSoon()
    case .ret: host.insert("\n"); refreshShiftSoon()
    case .shift:
      if -lastShiftTap.timeIntervalSinceNow < 0.35 { shift = .lock } else { shift = shift == .off ? .on : .off }
      lastShiftTap = Date()
      style()
    case .layer(let l): switchLayer(l)
    case .mic: host.mic()
    case .delete: break
    }
  }

  private func switchLayer(_ l: Layer) {
    layer_ = l
    build()
    refreshShift()
  }

  private func refreshShiftSoon() {
    DispatchQueue.main.async { [weak self] in self?.contextChanged() }
  }

  private func refreshShift() {
    guard layer_ == .letters, shift != .lock, let host else { return }
    let b = host.before
    var on = false
    switch host.autocap {
    case .allCharacters: on = true
    case .words: on = b.last.map { $0.isWhitespace } ?? true
    case .sentences:
      let trimmed = b.reversed().drop { $0 == " " }
      on = trimmed.isEmpty || trimmed.first == "\n" || (trimmed.count < b.count && ".!?".contains(trimmed.first!))
    default: break
    }
    let new = on ? Shift.on : .off
    if new != shift { shift = new; style() }
  }

  private func showPopup(_ k: KeyView, _ c: String) {
    let f = k.frame
    let bubble = CGRect(x: f.minX - 11, y: f.minY - 60, width: f.width + 22, height: 62)
    let path = UIBezierPath(roundedRect: bubble, cornerRadius: 11)
    path.append(UIBezierPath(rect: CGRect(x: f.minX, y: f.minY - 12, width: f.width, height: 24)))
    path.append(UIBezierPath(roundedRect: f, cornerRadius: 5))
    popup.path = path.cgPath
    popup.isHidden = false
    popupText.text = shift == .off ? c : c.uppercased()
    popupText.frame = CGRect(x: bubble.minX, y: bubble.minY + 2, width: bubble.width, height: 52)
    popupText.isHidden = false
  }

  private func hidePopup() {
    popup.isHidden = true
    popupText.isHidden = true
  }

  private func partial() -> String {
    guard let b = host?.before else { return "" }
    return String(b.reversed().prefix { $0.isLetter || $0 == "'" }.reversed())
  }

  private func suggestions() -> [String] {
    let w = partial()
    guard !w.isEmpty else { return shift == .off ? ["i", "the", "i'm"] : ["I", "The", "I'm"] }
    let lower = w.lowercased()
    let ns = w as NSString
    let range = NSRange(location: 0, length: ns.length)
    let valid = checker.rangeOfMisspelledWord(in: w, range: range, startingAt: 0, wrap: false, language: "en_US").location == NSNotFound
    var out: [String] = []
    if !valid && !history.contains(lower) { out.append("\"\(w)\"") }
    out += history.filter { $0.hasPrefix(lower) && $0 != lower }.prefix(3)
    out += checker.completions(forPartialWordRange: range, in: w, language: "en_US") ?? []
    if !valid { out += checker.guesses(forWordRange: range, in: w, language: "en_US") ?? [] }
    var seen = Set<String>()
    let cased = out.map { shift != .off || w.first?.isUppercase == true ? $0.prefix(1).uppercased() + $0.dropFirst() : $0 }
    return Array(cased.filter { seen.insert($0.lowercased()).inserted }.prefix(3))
  }

  private func accept(_ s: String) {
    guard let host else { return }
    let w = partial()
    if s.hasPrefix("\"") { host.insert(" "); return }
    for _ in 0..<w.count { host.delete() }
    host.insert(s + " ")
    refreshShiftSoon()
  }
}

final class SuggestionBar: UIView {
  var pick: ((String) -> Void)?
  private var buttons: [UIButton] = []
  private var dividers: [UIView] = []
  private let statusLabel = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)
    for _ in 0..<3 {
      let b = UIButton(type: .custom)
      b.titleLabel?.font = .systemFont(ofSize: 21)
      b.titleLabel?.lineBreakMode = .byTruncatingTail
      b.addAction(UIAction { [weak self, weak b] _ in if let t = b?.title(for: .normal), !t.isEmpty { self?.pick?(t) } }, for: .touchUpInside)
      addSubview(b)
      buttons.append(b)
    }
    for _ in 0..<2 {
      let d = UIView()
      addSubview(d)
      dividers.append(d)
    }
    statusLabel.font = .systemFont(ofSize: 15)
    statusLabel.textAlignment = .center
    statusLabel.isHidden = true
    addSubview(statusLabel)
  }

  required init?(coder: NSCoder) { fatalError() }

  func apply(text: UIColor, dark: Bool) {
    buttons.forEach { $0.setTitleColor(text.withAlphaComponent(0.6), for: .normal) }
    statusLabel.textColor = text.withAlphaComponent(0.7)
    dividers.forEach { $0.backgroundColor = dark ? UIColor(white: 1, alpha: 0.22) : UIColor(white: 0, alpha: 0.2) }
  }

  func show(_ items: [String], status: String?) {
    statusLabel.text = status
    statusLabel.isHidden = status == nil
    for (i, b) in buttons.enumerated() { b.setTitle(i < items.count ? items[i] : nil, for: .normal) }
    dividers.forEach { $0.isHidden = status != nil }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let w = bounds.width / 3
    for (i, b) in buttons.enumerated() { b.frame = CGRect(x: CGFloat(i) * w, y: 0, width: w, height: bounds.height) }
    for (i, d) in dividers.enumerated() { d.frame = CGRect(x: w * CGFloat(i + 1), y: 9, width: 1 / UIScreen.main.scale, height: bounds.height - 18) }
    statusLabel.frame = bounds
  }
}
