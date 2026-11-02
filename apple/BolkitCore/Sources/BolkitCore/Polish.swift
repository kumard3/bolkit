import Foundation

public enum Polish {
  static func re(_ p: String, _ o: NSRegularExpression.Options = [.caseInsensitive]) -> NSRegularExpression {
    try! NSRegularExpression(pattern: p, options: o)
  }

  static func sub(_ s: String, _ r: NSRegularExpression, _ with: String) -> String {
    r.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: NSRegularExpression.escapedTemplate(for: with))
  }

  nonisolated(unsafe) static let layout: [(NSRegularExpression, String)] = [
    (re(#"\b(new paragraph|next paragraph)\b[.,!?]*"#), "\n\n"),
    (re(#"\b(new line|next line)\b[.,!?]*"#), "\n"),
    (re(#"\b(bullet point|new bullet|bullet)\b[.,!?]*"#), "\n• "),
    (re(#"\b(numbered list|number list)\b[.,!?]*"#), "\n1. "),
  ]

  nonisolated(unsafe) static let punctuation: [(NSRegularExpression, String)] = [
    (re(#"\b(open paren|open parenthesis)\b"#), "("),
    (re(#"\b(close paren|close parenthesis)\b"#), ")"),
    (re(#"\b(open quote|quote)\b"#), "“"),
    (re(#"\b(close quote|unquote|end quote)\b"#), "”"),
    (re(#"\b(exclamation mark|exclamation point)\b"#), "!"),
    (re(#"\b(question mark)\b"#), "?"),
    (re(#"\b(full stop|period)\b"#), "."),
    (re(#"\b(comma)\b"#), ","),
    (re(#"\b(colon)\b"#), ":"),
    (re(#"\b(semicolon)\b"#), ";"),
    (re(#"\b(hyphen|dash)\b"#), "-"),
    (re(#"\b(smiley face|smiley)\b"#), ":)"),
  ]

  nonisolated(unsafe) static let fillers = re(#"\b(um+|uh+|erm+|uhh+|hmm+|mm+hmm|y'?know)\b"#)
  nonisolated(unsafe) static let scratch = re(#"[^.!?\n]*\b(?:scratch|strike|delete|cross)\s+that\b[.,!?]*"#)
  nonisolated(unsafe) static let lastWord = re(#"(?:\S+)\s+\b(?:scratch|delete|cross)\s+(?:the\s+)?last word\b[.,!?]*"#)
  nonisolated(unsafe) static let lastLine = re(#"\b(?:scratch|delete|cross)\s+(?:this |the |that )?last line\b[.,!?]*"#)
  static let now = "(?:so far|till now|until now|up to now|up till now)"
  static let time = "(?:so far|till now|until now|up to now|up till now|before|above|earlier)"
  static let qualifier = #"(?:\s+(?:(?:that|what|which)\s+)?i(?:\s+have|'ve|’ve)?\s+(?:said|told you|dictated|spoken|spoke|wrote|typed)(?:\s+"# + time + #")?|\s+"# + now + ")"
  nonisolated(unsafe) static let clearAllRe = re(#"\b(?:(?:delete|erase|scratch|clear|remove|cancel|forget|undo)\s+(?:everything|all of that|all of this|all of it|all that|all this|it all)|start\s+(?:over|again))\b("# + qualifier + #")?\b([.,!?;]*)"#)
  nonisolated(unsafe) static let andStartOver = re(#"^\s*and\s+start\s+(?:over|again)\b[.,!?;]*"#)

  static func clearAll(_ text: String) -> String {
    let ns = text as NSString
    var keepFrom = -1
    for m in clearAllRe.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
      var end = m.range.location + m.range.length
      let rest = ns.substring(from: end)
      let and = andStartOver.firstMatch(in: rest, range: NSRange(location: 0, length: (rest as NSString).length))
      if let and { end += and.range.length }
      let qualified = m.range(at: 1).length > 0 && m.range(at: 1).location != NSNotFound
      let punct = m.range(at: 2).length > 0 && m.range(at: 2).location != NSNotFound
      if rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || qualified || punct || and != nil { keepFrom = end }
    }
    guard keepFrom >= 0 else { return text }
    return sub(ns.substring(from: keepFrom), re(#"^[\s.,!?;:]+"#), "")
  }

  public static func edits(_ text: String) -> String {
    var t = sub(sub(clearAll(text), scratch, ""), lastWord, "")
    guard lastLine.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil else { return t }
    var out: [String] = []
    for line in t.components(separatedBy: "\n") {
      if let m = lastLine.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
        let before = (line as NSString).substring(to: m.range.location).trimmingCharacters(in: .whitespaces)
        if before.isEmpty, !out.isEmpty { out.removeLast() }
        continue
      }
      out.append(line)
    }
    t = out.joined(separator: "\n")
    return t
  }

  static func spaces(_ t: String) -> String {
    sub(sub(sub(t, re(#"[ \t]*\n[ \t]*"#), "\n"), re(#"[ \t]{2,}"#), " "), re(#"\n{3,}"#), "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public static func commands(_ text: String) -> String {
    spaces(layout.reduce(text) { sub($0, $1.0, $1.1) })
  }

  static func tidy(_ text: String) -> String {
    var t = re(#"[ \t]+([,.!?;:])"#).stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1")
    t = re(#"([,.!?;:])(?=[^\s\d)])"#).stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "$1 ")
    t = spaces(t)
    let caps = re(#"(^|[.!?]\s+|\n)([a-z])"#, [])
    for m in caps.matches(in: t, range: NSRange(t.startIndex..., in: t)).reversed() {
      let r = Range(m.range(at: 2), in: t)!
      t.replaceSubrange(r, with: t[r].uppercased())
    }
    return sub(t, re(#"\bi\b"#, []), "I")
  }

  public static func polish(_ text: String) -> String {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
    let t = (layout + punctuation).reduce(text) { sub($0, $1.0, $1.1) }
    return tidy(sub(t, fillers, " "))
  }
}
