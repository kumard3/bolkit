import Foundation

public enum Digest {
  static let stop: Set<String> = Set(("a an the and or but if then of to in on at by for with from into is are was were be been am do does did have has had will would can could may might must i you he she it we they me him her us them my your his its our their this that these those there here as so than too very just also not no yes about up down out off again what which who how why when where all any both each few more most other some such only own same").split(separator: " ").map(String.init))

  static func sentences(_ text: String) -> [String] {
    var out: [String] = []
    text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { s, _, _, _ in
      if let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { out.append(s) }
    }
    return out
  }

  static func words(_ s: String) -> [String] {
    s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
      .filter { $0.count >= 3 && !stop.contains($0) }
  }

  public static func summary(_ text: String, max n: Int = 3) -> String {
    let ss = sentences(text)
    guard ss.count > n else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var freq: [String: Int] = [:]
    ss.forEach { words($0).forEach { freq[$0, default: 0] += 1 } }
    let scored = ss.enumerated().map { i, s -> (Int, Double) in
      let w = words(s)
      return (i, w.isEmpty ? 0 : Double(w.reduce(0) { $0 + freq[$1, default: 0] }) / Double(w.count).squareRoot())
    }
    let keep = scored.sorted { $0.1 > $1.1 }.prefix(n).map(\.0).sorted()
    return keep.map { ss[$0] }.joined(separator: " ")
  }

  public static func decisions(_ text: String) -> [String] {
    let cues = ["we decided", "decided to", "we agreed", "agreed to", "let's ", "we will ", "we'll ", "action item", "next step"]
    return sentences(text).filter { s in cues.contains { s.lowercased().contains($0) } }.prefix(6).map { $0 }
  }

  public static func turns(from words: [(text: String, start: Double, end: Double)], gap: Double = 1.6) -> [Turn] {
    var out: [Turn] = []
    var last = -100.0
    for w in words {
      if w.start - last > gap || out.isEmpty {
        out.append(Turn(speaker: 0, text: w.text, start: w.start, end: w.end))
      } else {
        out[out.count - 1].text += " " + w.text
        out[out.count - 1].end = w.end
      }
      last = w.end
    }
    return out
  }
}
