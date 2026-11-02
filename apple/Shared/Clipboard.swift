import ImageIO
import UIKit
import UniformTypeIdentifiers

struct Clip: Codable {
  var id: String
  var text: String?
  var date: Date
  var isImage: Bool { text == nil }
}

@MainActor final class ClipStore {
  static let dir = (FlowShared.dir ?? .applicationSupportDirectory).appendingPathComponent("clipboard", isDirectory: true)
  private(set) var items: [Clip] = []
  private var seen = UserDefaults.standard.integer(forKey: "clipCount")
  private let thumbs = NSCache<NSString, UIImage>()

  init() {
    try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
    items = (try? Data(contentsOf: Self.dir.appendingPathComponent("index.json"))).flatMap { try? JSONDecoder().decode([Clip].self, from: $0) } ?? []
    prune()
  }

  func file(_ c: Clip) -> URL { Self.dir.appendingPathComponent(c.id + ".jpg") }

  func capture() {
    let pb = UIPasteboard.general
    guard pb.changeCount != seen else { return }
    seen = pb.changeCount
    UserDefaults.standard.set(seen, forKey: "clipCount")
    if pb.hasStrings, let s = pb.string, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      add(text: s)
    } else if pb.hasImages {
      for t in pb.types {
        guard let u = UTType(t), u.conforms(to: .image), let d = pb.data(forPasteboardType: t), add(image: d) else { continue }
        break
      }
    }
  }

  func add(text: String) {
    items.removeAll { $0.text == text }
    items.insert(Clip(id: UUID().uuidString, text: text, date: Date()), at: 0)
    prune()
  }

  @discardableResult
  func add(image data: Data) -> Bool {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil),
          let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1024] as CFDictionary),
          let jpg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.7) else { return false }
    let c = Clip(id: UUID().uuidString, text: nil, date: Date())
    guard (try? jpg.write(to: file(c))) != nil else { return false }
    items.insert(c, at: 0)
    prune()
    return true
  }

  func remove(_ c: Clip) {
    items.removeAll { $0.id == c.id }
    prune()
  }

  func clear() {
    items = []
    prune()
  }

  func image(_ c: Clip) -> UIImage? {
    if let i = thumbs.object(forKey: c.id as NSString) { return i }
    guard let i = UIImage(contentsOfFile: file(c).path)?.preparingThumbnail(of: CGSize(width: 360, height: 360)) else { return nil }
    thumbs.setObject(i, forKey: c.id as NSString)
    return i
  }

  func noteOwnWrite() {
    seen = UIPasteboard.general.changeCount
    UserDefaults.standard.set(seen, forKey: "clipCount")
  }

  private func prune() {
    let now = Date()
    var texts = 0, images = 0
    let kept = items.filter { c in
      if c.isImage { images += 1; return images <= 10 && now.timeIntervalSince(c.date) < 86400 }
      texts += 1
      return texts <= 50 && now.timeIntervalSince(c.date) < 7 * 86400
    }
    let keep = Set(kept.map(\.id))
    for c in items where c.isImage && !keep.contains(c.id) { try? FileManager.default.removeItem(at: file(c)) }
    items = kept
    if let d = try? JSONEncoder().encode(items) { try? d.write(to: Self.dir.appendingPathComponent("index.json"), options: .atomic) }
  }
}

final class ClipboardPanel: UIView {
  var store: ClipStore!
  var insert: ((String) -> Void)?
  var back: (() -> Void)?
  var fullAccess = true
  var images = false
  private var dark = true
  private let abc = UIButton(type: .custom)
  private let tabs = UISegmentedControl(items: ["Text", "Images"])
  private let clear = UIButton(type: .custom)
  private let hint = UILabel()
  private let scroll = UIScrollView()

  override init(frame: CGRect) {
    super.init(frame: frame)
    for (b, t) in [(abc, "ABC"), (clear, "Clear all")] {
      b.setTitle(t, for: .normal)
      b.titleLabel?.font = .systemFont(ofSize: 15)
      b.layer.cornerRadius = 8
      b.layer.cornerCurve = .continuous
      addSubview(b)
    }
    abc.addAction(UIAction { [weak self] _ in self?.back?() }, for: .touchUpInside)
    tabs.selectedSegmentIndex = 0
    tabs.addAction(UIAction { [weak self] _ in
      guard let self else { return }
      images = tabs.selectedSegmentIndex == 1
      reload()
    }, for: .valueChanged)
    addSubview(tabs)
    clear.addAction(UIAction { [weak self] _ in self?.store.clear(); self?.reload() }, for: .touchUpInside)
    hint.font = .systemFont(ofSize: 15)
    hint.textAlignment = .center
    hint.isHidden = true
    addSubview(hint)
    scroll.showsVerticalScrollIndicator = false
    addSubview(scroll)
  }

  required init?(coder: NSCoder) { fatalError() }

  func apply(dark: Bool) {
    self.dark = dark
    reload()
  }

  private var key: UIColor { dark ? UIColor(white: 0.267, alpha: 1) : .white }
  private var ink: UIColor { dark ? .white : .black }

  func reload() {
    for b in [abc, clear] {
      b.setTitleColor(ink, for: .normal)
      b.backgroundColor = key
    }
    if tabs.selectedSegmentIndex != (images ? 1 : 0) { tabs.selectedSegmentIndex = images ? 1 : 0 }
    tabs.overrideUserInterfaceStyle = dark ? .dark : .light
    tabs.backgroundColor = key
    tabs.selectedSegmentTintColor = dark ? UIColor(white: 0.45, alpha: 1) : UIColor(white: 0.82, alpha: 1)
    tabs.setTitleTextAttributes([.foregroundColor: ink, .font: UIFont.systemFont(ofSize: 15)], for: .normal)
    tabs.setTitleTextAttributes([.foregroundColor: ink, .font: UIFont.systemFont(ofSize: 15, weight: .medium)], for: .selected)
    hint.textColor = ink
    scroll.subviews.forEach { $0.removeFromSuperview() }
    let items = store.items.filter { $0.isImage == images }
    if items.isEmpty {
      let l = UILabel(frame: CGRect(x: 16, y: 20, width: max(bounds.width - 32, 0), height: 60))
      l.numberOfLines = 3
      l.textAlignment = .center
      l.font = .systemFont(ofSize: 15)
      l.textColor = ink.withAlphaComponent(0.55)
      l.text = fullAccess ? (images ? "No copied images yet" : "Nothing copied yet") : "Turn on Allow Full Access for Bolkit in Settings to use the clipboard"
      scroll.addSubview(l)
      scroll.contentSize = .zero
      return
    }
    let side: CGFloat = 6.7, gap: CGFloat = 6.3
    let w = (bounds.width - 2 * side - gap) / 2
    let h: CGFloat = images ? 92 : 66
    for (i, c) in items.enumerated() {
      let f = CGRect(x: side + CGFloat(i % 2) * (w + gap), y: CGFloat(i / 2) * (h + gap), width: w, height: h)
      let tile = UIButton(type: .custom)
      tile.frame = f
      tile.backgroundColor = key
      tile.layer.cornerRadius = 8
      tile.layer.cornerCurve = .continuous
      tile.clipsToBounds = true
      if images {
        let v = UIImageView(image: store.image(c))
        v.frame = tile.bounds
        v.contentMode = .scaleAspectFill
        v.isUserInteractionEnabled = false
        tile.addSubview(v)
      } else {
        let l = UILabel()
        l.numberOfLines = 3
        l.font = .systemFont(ofSize: 14)
        l.textColor = ink
        l.text = c.text
        let tw = tile.bounds.width - 38
        l.frame = CGRect(x: 10, y: 8, width: tw, height: min(l.sizeThatFits(CGSize(width: tw, height: .greatestFiniteMagnitude)).height, tile.bounds.height - 16))
        l.isUserInteractionEnabled = false
        tile.addSubview(l)
      }
      tile.addAction(UIAction { [weak self] _ in self?.pick(c) }, for: .touchUpInside)
      let x = UIButton(type: .custom)
      x.frame = CGRect(x: f.maxX - 30, y: f.minY + 4, width: 26, height: 26)
      x.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15)), for: .normal)
      x.tintColor = images ? .white : ink.withAlphaComponent(0.5)
      x.addAction(UIAction { [weak self] _ in self?.store.remove(c); self?.reload() }, for: .touchUpInside)
      scroll.addSubview(tile)
      scroll.addSubview(x)
    }
    scroll.contentSize = CGSize(width: bounds.width, height: CGFloat((items.count + 1) / 2) * (h + gap))
  }

  private func pick(_ c: Clip) {
    if let t = c.text { insert?(t); return }
    guard let i = UIImage(contentsOfFile: store.file(c).path) else { return }
    UIPasteboard.general.image = i
    store.noteOwnWrite()
    hint.text = "Copied. Now paste"
    hint.isHidden = false
    tabs.isHidden = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
      self?.hint.isHidden = true
      self?.tabs.isHidden = false
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let w = bounds.width, side: CGFloat = 6.7
    abc.frame = CGRect(x: side, y: 2, width: 64, height: 34)
    clear.frame = CGRect(x: w - side - 88, y: 2, width: 88, height: 34)
    tabs.frame = CGRect(x: (w - 160) / 2, y: 2, width: 160, height: 34)
    hint.frame = CGRect(x: 80, y: 2, width: w - 180, height: 34)
    scroll.frame = CGRect(x: 0, y: 44, width: w, height: bounds.height - 44)
    if scroll.subviews.isEmpty || scroll.contentSize.width != w { reload() }
    tabs.layoutIfNeeded()
  }
}
