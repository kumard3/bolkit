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

  public static func turns(from words: [Word], segments: [(start: Double, end: Double, speaker: Int)] = [], gap: Double = 1.6) -> [Turn] {
    func speaker(_ w: Word, _ prev: Int) -> Int {
      var best = (overlap: 0.0, speaker: prev)
      for s in segments {
        let o = min(w.end, s.end) - max(w.start, s.start)
        if o > best.overlap { best = (o, s.speaker) }
      }
      return best.speaker
    }
    var out: [Turn] = []
    var last = -100.0
    for w in words {
      let sp = speaker(w, out.last?.speaker ?? 0)
      if out.isEmpty || sp != out[out.count - 1].speaker || w.start - last > gap {
        out.append(Turn(speaker: sp, text: w.text, start: w.start, end: w.end))
      } else {
        out[out.count - 1].text += " " + w.text
        out[out.count - 1].end = w.end
      }
      last = w.end
    }
    return out
  }

  public static func clock(_ t: Double) -> String {
    let s = Int(t)
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
  }

  public static func windows(_ turns: [Turn], name: (Int) -> String, limit: Int = 7000) -> [(text: String, start: Double)] {
    var out: [(text: String, start: Double)] = []
    var current = "", start = 0.0
    for t in turns {
      let line = "[\(clock(t.start ?? 0))] \(name(t.speaker)): \(t.text)"
      if !current.isEmpty, current.count + line.count > limit { out.append((current, start)); current = "" }
      if current.isEmpty { start = t.start ?? 0 }
      if line.count > limit {
        var rest = Substring(line)
        while !rest.isEmpty { out.append((String(rest.prefix(limit)), t.start ?? 0)); rest = rest.dropFirst(limit) }
      } else {
        current += (current.isEmpty ? "" : "\n\n") + line
      }
    }
    if !current.isEmpty { out.append((current, start)) }
    return out
  }

  public static func sections(_ text: String) -> [String: [String]] {
    var out: [String: [String]] = [:]
    var key = ""
    for raw in text.split(whereSeparator: \.isNewline) {
      let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: " *#-•\t"))
      let low = line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":"))
      if ["key points", "decisions", "suggestions", "action items"].contains(low) { key = low; continue }
      if !key.isEmpty, !line.isEmpty, !["none", "none."].contains(line.lowercased()) { out[key, default: []].append(line) }
    }
    return out
  }
}
