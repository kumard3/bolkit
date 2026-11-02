import Foundation

public enum Corrections {
  public static let instruction = """
    You apply a speaker's spoken self-corrections to their dictation. When the speaker takes \
    something back or corrects it ("scratch that", "no wait", "actually", "I mean", "sorry", \
    "make that", "delete everything I said"), remove the words they took back and the \
    correction phrase itself, and keep the correction. If they ask to delete everything said so \
    far, keep only what comes after that request. Do not add, reword, reorder, translate or \
    re-punctuate anything else. If there is no self-correction, return the text unchanged. \
    Output only the final text.

    Examples:
    In: let's meet at 2 actually 3 pm
    Out: let's meet at 3 pm
    In: send it to Rahul no wait send it to Priya
    Out: send it to Priya
    In: no no no delete everything I said till now the meeting is moved to Friday
    Out: the meeting is moved to Friday
    In: I actually liked the demo
    Out: I actually liked the demo
    """

  nonisolated(unsafe) static let cues = try! NSRegularExpression(
    pattern: #"\b(?:scratch that|delete that|ignore that|forget that|delete everything|scratch everything|erase everything|start over|no wait|wait no|actually no|no actually|i meant|i mean|sorry|correction|make that|rather|let me rephrase|oops|actually|no no)\b"#,
    options: .caseInsensitive)
  static let fillers: Set<String> = ["um", "uh", "er", "erm", "ah", "hmm"]
  static let soft: Set<String> = ["actually", "sorry", "rather", "oops"]

  public static func cueCount(_ s: String) -> Int { cues.numberOfMatches(in: s, range: NSRange(s.startIndex..., in: s)) }

  static func tokens(_ s: String) -> [String] {
    s.lowercased().replacingOccurrences(of: "’", with: "'")
      .split { !($0.isLetter || $0.isNumber || $0 == "'") }
      .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
      .filter { !$0.isEmpty && !fillers.contains($0) }
  }

  public static func accept(_ raw: String, _ candidate: String) -> Bool {
    let r = tokens(raw), c = tokens(candidate)
    guard !c.isEmpty, c.count < r.count else { return false }
    var removed: [String] = [], j = 0
    for t in r { if j < c.count, t == c[j] { j += 1 } else { removed.append(t) } }
    guard j == c.count, cueCount(candidate) < cueCount(raw) else { return false }
    return !removed.allSatisfy(soft.contains)
  }
}
