import BolkitCore
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum Brain {
  static var available: Bool {
    #if canImport(FoundationModels)
    if #available(iOS 26, *) { return SystemLanguageModel.default.availability == .available }
    #endif
    return false
  }

  static func run(_ instruction: String, _ text: String) async -> String? {
    #if canImport(FoundationModels)
    if #available(iOS 26, *), available {
      do { return try await LanguageModelSession(instructions: instruction).respond(to: text).content } catch { return nil }
    }
    #endif
    return nil
  }

  static func instruction(vocab: [String]) -> String {
    "Summarise this meeting transcript for the attendees. Use short bullet points under the headings " +
      "Key points, Decisions, Suggestions, Action items (write none when empty). " +
      "Decisions are only what the people explicitly agreed or settled. An idea that was proposed, floated or " +
      "\"we could / we should\" without agreement goes under Suggestions, never Decisions. " +
      "Each Action item is one line: Owner: task [mm:ss], where Owner is the person who took it on, " +
      "or Unassigned when nobody did, and [mm:ss] is the timestamp of the line where it was said, copied from the transcript. " +
      "Use speaker names as given. Same language as the transcript. Do not add facts. Output only the summary." +
      (vocab.isEmpty ? "" : " Spell these names and terms exactly this way, and fix mishearings of them: \(vocab.joined(separator: ", ")).")
  }

  static func clean(_ s: String?) -> String? {
    let t = s?.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " .\"'`*#")) }
    return t.flatMap { $0.isEmpty ? nil : String($0.prefix(60)) }
  }

  static func enrich(_ m: inout Meeting, vocab: [String], you: String) async {
    guard available, let turns = m.turns, !turns.isEmpty else { return }
    let parts = Digest.windows(turns, name: { $0 == 0 && m.speakerNames?["0"] == nil && m.speakers.count == 1 ? (you.isEmpty ? "Speaker" : you) : m.name($0) })
    let ins = instruction(vocab: vocab)
    var partials: [String] = []
    for p in parts { if let r = await run(ins, p.text) { partials.append(r) } }
    guard !partials.isEmpty else { return }
    var full = partials[0]
    if partials.count > 1 {
      full = await run("These are summaries of consecutive parts of ONE meeting. Write a single summary of the whole meeting with each heading (Key points, Decisions, Suggestions, Action items) exactly once, and short bullet points under each. Combine and de-duplicate the bullets. Keep Decisions and Suggestions apart. Keep every action item as one line Owner: task [mm:ss] with its original [mm:ss]. Output only the summary.", partials.joined(separator: "\n\n")) ?? partials[0]
    }
    let sec = Digest.sections(full)
    m.summary = full
    m.decisions = sec["decisions"]
    m.suggestions = sec["suggestions"]
    m.actions = sec["action items"]
    if let t = clean(await run("Name this meeting in at most 6 words, as a short title a person would give it. Output only the title.", full)) { m.title = t }
    var found: [(String, Double)] = []
    for p in parts {
      if let t = clean(await run("Give a topic title of at most 6 words for this part of a meeting. Output only the title.", p.text)), t != found.last?.0, p.start > (found.last?.1 ?? -1) { found.append((t, p.start)) }
    }
    m.chapters = found.enumerated().map { i, c in Chapter(title: c.0, start: c.1, end: i + 1 < found.count ? found[i + 1].1 : max(m.durationSec, c.1)) }
  }
}
