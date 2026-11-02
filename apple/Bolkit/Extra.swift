import BolkitCore
import FluidAudio
import Foundation
import Voz

struct Seg: Sendable { let start: Double, end: Double, speaker: Int }

actor Engines {
  static let shared = Engines()
  var voz: Voz?
  var parakeet: [String: AsrManager] = [:]

  func vozTranscribe(_ samples: [Float], vocab: [String]) async throws -> [BolkitCore.Word] {
    if voz == nil { voz = try await Voz(cacheRoot: Extra.appSupport) }
    let r = try await voz!.transcribe(samples: samples, vocabulary: vocab)
    return r.words.map { BolkitCore.Word(text: $0.text.trimmingCharacters(in: .whitespaces), start: $0.start, end: $0.end) }.filter { !$0.text.isEmpty }
  }

  func parakeetTranscribe(_ samples: [Float], _ info: ModelInfo) async throws -> [BolkitCore.Word] {
    if parakeet[info.id] == nil {
      let m = AsrManager(config: .default)
      try await m.loadModels(try await AsrModels.downloadAndLoad(version: Extra.version(info)))
      parakeet[info.id] = m
    }
    var state = try TdtDecoderState()
    let r = try await parakeet[info.id]!.transcribe(samples, decoderState: &state)
    var words: [BolkitCore.Word] = []
    for t in r.tokenTimings ?? [] {
      let piece = t.token.replacingOccurrences(of: "▁", with: " ")
      if piece.hasPrefix(" ") || words.isEmpty {
        let w = piece.trimmingCharacters(in: .whitespaces)
        if !w.isEmpty { words.append(BolkitCore.Word(text: w, start: t.startTime, end: t.endTime)) }
      } else if let last = words.popLast() {
        words.append(BolkitCore.Word(text: last.text + piece, start: last.start, end: t.endTime))
      }
    }
    return words
  }

  func diarize(_ samples: [Float]) async throws -> [Seg] {
    let d = OfflineSortformerDiarizer(config: .offlineV2_1, timelineConfig: .sortformerDefault)
    try await d.initializeFromHuggingFace()
    let timeline = try d.processComplete(samples)
    return timeline.speakers.values.flatMap(\.finalizedSegments)
      .map { Seg(start: Double($0.startTime), end: Double($0.endTime), speaker: $0.speakerIndex) }
      .sorted { $0.start < $1.start }
  }

  func dropVoz() { voz = nil }
  func dropParakeet() { parakeet = [:] }
}

enum Extra {
  static var appSupport: String { URL.applicationSupportDirectory.path }
  static var fluidModels: URL { URL.applicationSupportDirectory.appendingPathComponent("FluidAudio/Models", isDirectory: true) }

  static func fluidDirs(_ key: String) -> [URL] {
    ((try? FileManager.default.contentsOfDirectory(at: fluidModels, includingPropertiesForKeys: nil)) ?? [])
      .filter { $0.lastPathComponent.lowercased().contains(key) }
  }

  static func vozInstalled() -> Bool { Voz.isDownloaded(cacheRoot: appSupport) }
  static func vozDownload(_ p: @escaping @Sendable (Double) -> Void) async throws {
    try await Voz.download(cacheRoot: appSupport) { p($0.fraction) }
  }
  static func vozDelete() {
    Task { await Engines.shared.dropVoz() }
    try? FileManager.default.removeItem(atPath: appSupport + "/desert-ant-models")
  }

  static func version(_ info: ModelInfo) -> AsrModelVersion { info.id == "parakeet-v2" ? .v2 : .v3 }
  static func parakeetInstalled(_ info: ModelInfo) -> Bool { AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: version(info))) }
  static func parakeetDownload(_ info: ModelInfo, _ p: @escaping @Sendable (Double) -> Void) async throws {
    _ = try await AsrModels.downloadAndLoad(version: version(info), progressHandler: { p($0.fractionCompleted) })
  }
  static func parakeetDelete(_ info: ModelInfo) {
    Task { await Engines.shared.dropParakeet() }
    try? FileManager.default.removeItem(at: AsrModels.defaultCacheDirectory(for: version(info)))
  }

  static func sortformerInstalled() -> Bool { !fluidDirs("sortformer").isEmpty }
  static func sortformerDownload(_ p: @escaping @Sendable (Double) -> Void) async throws {
    let d = OfflineSortformerDiarizer(config: .offlineV2_1, timelineConfig: .sortformerDefault)
    try await d.initializeFromHuggingFace(progressHandler: { p($0.fractionCompleted) })
  }
  static func sortformerDelete() { fluidDirs("sortformer").forEach { try? FileManager.default.removeItem(at: $0) } }

  @MainActor static func transcribe(_ info: ModelInfo, file: URL, app: AppModel) async throws -> [BolkitCore.Word] {
    let samples = try Audio.samples(file)
    switch info.kind {
    case .voz: return try await Engines.shared.vozTranscribe(samples, vocab: app.vocab)
    case .parakeet: return try await Engines.shared.parakeetTranscribe(samples, info)
    case .sherpa: return try await Sherpa.transcribe(info, dir: app.models.url(info), samples: samples, lang: app.shortLang)
    default: throw SpeechError("\(info.title) is not available yet")
    }
  }
}
