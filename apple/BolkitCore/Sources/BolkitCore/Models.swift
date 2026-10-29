import Foundation

public struct Turn: Codable, Equatable, Sendable {
  public var speaker: Int
  public var text: String
  public var start: Double?
  public var end: Double?
  public init(speaker: Int, text: String, start: Double? = nil, end: Double? = nil) {
    self.speaker = speaker; self.text = text; self.start = start; self.end = end
  }
}

public struct Chapter: Codable, Equatable, Sendable {
  public var title: String
  public var start: Double
  public var end: Double
}

public struct Meeting: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var title: String
  public var createdAt: Double
  public var durationSec: Double
  public var language: String
  public var transcript: String
  public var turns: [Turn]?
  public var speakerNames: [String: String]?
  public var summary: String?
  public var decisions: [String]?
  public var chapters: [Chapter]?
  public var hasAudio: Bool

  public init(id: String, title: String, createdAt: Double, durationSec: Double, language: String,
              transcript: String, turns: [Turn]? = nil, summary: String? = nil,
              decisions: [String]? = nil, hasAudio: Bool) {
    self.id = id; self.title = title; self.createdAt = createdAt; self.durationSec = durationSec
    self.language = language; self.transcript = transcript; self.turns = turns
    self.summary = summary; self.decisions = decisions; self.hasAudio = hasAudio
  }

  public var date: Date { Date(timeIntervalSince1970: createdAt / 1000) }
  public var speakers: [Int] { Array(Set((turns ?? []).map(\.speaker))).sorted() }

  public func name(_ speaker: Int) -> String { speakerNames?[String(speaker)] ?? "Speaker \(speaker + 1)" }

  public var fullText: String {
    guard let turns, turns.count > 1, speakers.count > 1 else { return transcript }
    return turns.map { "\(name($0.speaker)): \($0.text)" }.joined(separator: "\n\n")
  }

  public static func defaultTitle(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "d MMM, h:mm a"
    return "Meeting \(f.string(from: date))"
  }
}

public struct HistoryItem: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var text: String
  public var language: String
  public var translated: Bool
  public var translatedTo: String?
  public var createdAt: Double

  public init(text: String, language: String) {
    let now = Date().timeIntervalSince1970 * 1000
    id = "\(Int(now))-\(Int.random(in: 0..<1_000_000))"
    self.text = text; self.language = language; translated = false; createdAt = now
  }

  public var date: Date { Date(timeIntervalSince1970: createdAt / 1000) }
}

public func durationLabel(_ sec: Double) -> String {
  let s = max(0, Int(sec.rounded())), m = s / 60
  return m < 60 ? String(format: "%d:%02d", m, s % 60) : "\(m / 60)h \(m % 60)m"
}

public struct Word: Sendable {
  public let text: String
  public let start: Double
  public let end: Double
  public init(text: String, start: Double, end: Double) { self.text = text; self.start = start; self.end = end }
}
