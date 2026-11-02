import UIKit

@MainActor protocol KeyboardHost: AnyObject {
  var before: String { get }
  var returnType: UIReturnKeyType { get }
  var autocap: UITextAutocapitalizationType { get }
  var appearance: UIKeyboardAppearance { get }
  var keyType: UIKeyboardType { get }
  var secure: Bool { get }
  var autocorrect: UITextAutocorrectionType { get }
  func insert(_ s: String)
  func delete()
  func move(_ n: Int)
  var fullAccess: Bool { get }
  var needsGlobe: Bool { get }
  func globe()
  func mic()
}

enum MicState { case ready, listening, working, done }

enum Layer { case letters, numbers, symbols }

enum KeyKind: Equatable {
  case char(String), shift, delete, layer(Layer), mic, space, ret, clip, globe
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

  static let height: CGFloat = 263
  let side: CGFloat = 6.7, gap: CGFloat = 6.3
  var onHeight: ((CGFloat) -> Void)?
  private var lastHeight: CGFloat = 0

  var forceLandscape = false
  var landscape: Bool { forceLandscape || bounds.width > 500 }
  var wantsBar: Bool {
    guard let h = host else { return true }
    return !(h.secure || h.autocorrect == .no || [.URL, .emailAddress, .phonePad, .numberPad, .decimalPad].contains(h.keyType))
  }
  private var fullBar: CGFloat { wantsBar ? (landscape ? 36 : 46) : 0 }
  var barHeight: CGFloat { panel.isHidden ? fullBar : 0 }
  var keyHeight: CGFloat { landscape ? 34 : 43 }
  var rowGap: CGFloat { landscape ? 8 : 11 }
  var top: CGFloat { barHeight == 0 ? (landscape ? 6 : 10) : (landscape ? 4 : 6) }
  private var normalHeight: CGFloat { fullBar + (fullBar == 0 ? (landscape ? 6 : 10) : (landscape ? 4 : 6)) + 4 * keyHeight + 3 * rowGap + 6 }
  var preferredHeight: CGFloat {
    guard !panel.isHidden else { return normalHeight }
    let screen = UIScreen.main.bounds.height
    return min(normalHeight * 1.5, screen * (landscape ? 0.75 : 0.5))
  }

  private func updateHeight() {
    let h = preferredHeight
    guard abs(h - lastHeight) > 0.5 else { return }
    lastHeight = h
    DispatchQueue.main.async { [weak self] in self?.onHeight?(h) }
  }

  weak var host: KeyboardHost?
  private var layer_ = Layer.letters
  private var built: (UIKeyboardType, UIReturnKeyType, Bool, Bool) = (.default, .default, false, true)
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
  private let chrome = UIView()
  private let panel = ClipboardPanel()
  private let clips = ClipStore()
  private var clipTimer: Timer?

  init(host: KeyboardHost?) {
    self.host = host
    super.init(frame: .zero, inputViewStyle: .default)
    chrome.layer.cornerRadius = 38
    chrome.layer.cornerCurve = .continuous
    chrome.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    insertSubview(chrome, at: 0)
    panel.store = clips
    panel.isHidden = true
    panel.insert = { [weak self] t in self?.host?.insert(t); self?.refreshShiftSoon() }
    panel.back = { [weak self] in self?.showClips(false) }
    bar.onClip = { [weak self] in self?.showClips(self?.panel.isHidden == true) }
    addSubview(panel)
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

  func rebuild() { build() }

  func showClips(_ on: Bool) {
    if on { captureClip() }
    panel.isHidden = !on
    keys.flatMap { $0 }.forEach { $0.isHidden = on }
    bar.clipOn = on
    setNeedsLayout()
    if on { panel.apply(dark: dark) }
  }

  private func captureClip() {
    if host?.fullAccess ?? true { clips.capture() }
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    clipTimer?.invalidate()
    clipTimer = nil
    guard window != nil else { return }
    captureClip()
    clipTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        let n = self.clips.items.count
        self.captureClip()
        if !self.panel.isHidden, n != self.clips.items.count { self.panel.reload() }
      }
    }
  }

  func seed(_ texts: [String], image: Data?, images: Bool = false) {
    panel.images = images
    texts.reversed().forEach { clips.add(text: $0) }
    if let image { clips.add(image: image) }
  }

  private var signature: (UIKeyboardType, UIReturnKeyType, Bool, Bool) {
    (host?.keyType ?? .default, host?.returnType ?? .default, !(host?.before.isEmpty ?? true), wantsBar)
  }

  func contextChanged() {
    captureClip()
    let sig = signature
    if sig != built {
      let old = built
      let typeChanged = sig.0 != built.0
      built = sig
      if typeChanged, [.numberPad, .phonePad, .decimalPad, .numbersAndPunctuation, .asciiCapableNumberPad].contains(sig.0) { layer_ = .numbers } else if typeChanged { layer_ = .letters }
      typeChanged || sig.3 != old.3 ? build() : style()
      setNeedsLayout()
    }
    refreshShift()
    if status == nil { bar.show(suggestions(), status: nil) }
  }

  private func rows() -> [[KeyKind]] {
    var extra: [KeyKind] = []
    switch host?.keyType ?? .default {
    case .URL, .webSearch: extra = [.char(".")]
    case .emailAddress: extra = [.char("@"), .char(".")]
    case .twitter: extra = [.char("@"), .char("#")]
    default: break
    }
    let bottom: [KeyKind] = (host?.needsGlobe == true ? [.globe] : []) + [.layer(layer_ == .letters ? .numbers : .letters)] + (wantsBar ? [] : [.clip]) + [.mic, .space] + extra + [.ret]
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
    built = signature
    keys = rows().map { $0.map { KeyView($0) } }
    if !panel.isHidden { keys.flatMap { $0 }.forEach { $0.isHidden = true } }
    keys.flatMap { $0 }.forEach { insertSubview($0, belowSubview: popupText) }
    style()
    setNeedsLayout()
  }

  private func style() {
    let p = palette
    chrome.backgroundColor = dark ? UIColor(white: 0.125, alpha: 1) : UIColor(red: 0.886, green: 0.894, blue: 0.91, alpha: 1)
    panel.fullAccess = host?.fullAccess ?? true
    panel.apply(dark: dark)
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
        var size: CGFloat = 17
        switch k.kind {
        case .char(let c): title = shift == .off ? c : c.uppercased(); size = 27
        case .space: title = nil
        case .shift:
          symbol = shift == .lock ? "capslock.fill" : shift == .on ? "shift.fill" : "shift"
          if shift != .off { fill = dark ? UIColor(white: 0.95, alpha: 1) : .white; tint = .black }
        case .delete: symbol = "delete.left"
        case .clip: symbol = "doc.on.clipboard"
        case .globe: symbol = "globe"
        case .layer(let l): title = l == .letters ? "ABC" : l == .numbers ? "123" : "#+="
        case .mic:
          symbol = micState == .listening ? "waveform" : micState == .done ? "checkmark" : "mic.fill"
          if micState == .listening { fill = .systemRed; tint = .white }
          if micState == .working { tint = tint.withAlphaComponent(0.4) }
        case .ret:
          let web = [.URL, .webSearch].contains(host?.keyType ?? .default) && (ret == .go || ret == .search)
          if web { symbol = "arrow.right" } else if let t = Self.returnTitle(ret) { title = t } else { symbol = "return" }
          let goes = [.go, .google, .search, .yahoo, .route, .join, .continue].contains(ret)
          if Self.accent(ret) && (!goes || !(host?.before.isEmpty ?? true)) { fill = .systemBlue; tint = .white }
        }
        k.backgroundColor = fill
        if k.kind == .mic {
          k.layer.removeAnimation(forKey: "pulse")
          if micState == .listening {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1
            a.toValue = 0.55
            a.duration = 0.7
            a.autoreverses = true
            a.repeatCount = .infinity
            k.layer.add(a, forKey: "pulse")
          }
        }
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
    chrome.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height + 90)
    bar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: fullBar)
    bar.isHidden = barHeight == 0
    updateHeight()
    panel.frame = CGRect(x: 0, y: barHeight + 4, width: bounds.width, height: bounds.height - barHeight - 4)
    let w = bounds.width
    let kw = (w - 2 * side - 9 * gap) / 10
    let wide = (w - 2 * side - 7 * kw - 6 * gap) / 2 - 13.7
    for (r, row) in keys.enumerated() {
      let y = barHeight + top + CGFloat(r) * (keyHeight + rowGap)
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
        let unit = kw * 1.3, ret = kw * 2.8
        var ws = row.map { k -> CGFloat in
          switch k.kind {
          case .layer, .mic, .clip, .globe: unit
          case .ret: ret
          case .char: kw
          default: 0
          }
        }
        let rest = w - 2 * side - ws.reduce(0, +) - CGFloat(row.count - 1) * gap
        if let i = row.firstIndex(where: { $0.kind == .space }) { ws[i] = rest }
        place(row, y: y, x: side, widths: ws)
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
    guard p.y > barHeight else { return nil }
    return all.min { dist($0.frame, p) < dist($1.frame, p) }
  }

  private func dist(_ r: CGRect, _ p: CGPoint) -> CGFloat {
    let dx = max(r.minX - p.x, 0, p.x - r.maxX), dy = max(r.minY - p.y, 0, p.y - r.maxY)
    return dx * dx + dy * dy
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard panel.isHidden else { return }
    for t in touches {
      let p = t.location(in: self)
      guard p.y > barHeight - 8, let k = key(at: p) else { continue }
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
    case .clip: showClips(true)
    case .globe: host.globe()
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
  var onClip: (() -> Void)?
  var clipOn = false { didSet { clip.backgroundColor = clipOn ? UIColor.white.withAlphaComponent(0.18) : nil } }
  private let clip = UIButton(type: .custom)
  private var ink = UIColor.white
  private var buttons: [UIButton] = []
  private var dividers: [UIView] = []
  private let statusLabel = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)
    for _ in 0..<3 {
      let b = UIButton(type: .custom)
      b.titleLabel?.font = .systemFont(ofSize: 20)
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
    clip.setImage(UIImage(systemName: "doc.on.clipboard", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17)), for: .normal)
    clip.layer.cornerRadius = 8
    clip.addAction(UIAction { [weak self] _ in self?.onClip?() }, for: .touchUpInside)
    addSubview(clip)
    statusLabel.font = .systemFont(ofSize: 15)
    statusLabel.textAlignment = .center
    statusLabel.isHidden = true
    addSubview(statusLabel)
  }

  required init?(coder: NSCoder) { fatalError() }

  func apply(text: UIColor, dark: Bool) {
    buttons.forEach { $0.setTitleColor(text.withAlphaComponent(0.6), for: .normal) }
    clip.tintColor = text.withAlphaComponent(0.75)
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
    let w = (bounds.width - 44) / 3
    clip.frame = CGRect(x: bounds.width - 42, y: 6, width: 38, height: bounds.height - 12)
    for (i, b) in buttons.enumerated() { b.frame = CGRect(x: CGFloat(i) * w, y: 0, width: w, height: bounds.height) }
    for (i, d) in dividers.enumerated() { d.frame = CGRect(x: w * CGFloat(i + 1), y: 9, width: 1 / UIScreen.main.scale, height: bounds.height - 18) }
    statusLabel.frame = CGRect(x: 0, y: 0, width: bounds.width - 44, height: bounds.height)
  }
}
