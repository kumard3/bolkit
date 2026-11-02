import AVFoundation
import BolkitCore
import SherpaKit

enum Sherpa {
  static let releases = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/"

  static func find(_ dir: URL, _ prefix: String) -> String {
    let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    let hits = names.filter { $0.hasPrefix(prefix) && ($0.hasSuffix(".onnx") || $0.hasSuffix(".ort") || $0.hasSuffix(".txt")) }
    return dir.appendingPathComponent(hits.first { $0.contains("int8") } ?? hits.first ?? prefix).path
  }

  static func online(_ dir: URL, endpoints: Bool) -> SherpaOnnxRecognizer {
    let mc = sherpaOnnxOnlineModelConfig(
      tokens: find(dir, "tokens"),
      transducer: sherpaOnnxOnlineTransducerModelConfig(encoder: find(dir, "encoder"), decoder: find(dir, "decoder"), joiner: find(dir, "joiner")),
      numThreads: 2)
    var cfg = sherpaOnnxOnlineRecognizerConfig(featConfig: sherpaOnnxFeatureConfig(), modelConfig: mc, enableEndpoint: endpoints)
    return SherpaOnnxRecognizer(config: &cfg)
  }

  static func offline(_ info: ModelInfo, _ dir: URL, lang: String) -> SherpaOnnxOfflineRecognizer {
    let tokens = find(dir, "tokens")
    var mc: SherpaOnnxOfflineModelConfig
    switch info.family {
    case "nemoCtc":
      mc = sherpaOnnxOfflineModelConfig(tokens: tokens, nemoCtc: sherpaOnnxOfflineNemoEncDecCtcModelConfig(model: find(dir, "model")), numThreads: 2)
    case "canary":
      let l = ["en", "es", "de", "fr"].contains(lang) ? lang : "en"
      mc = sherpaOnnxOfflineModelConfig(tokens: tokens, numThreads: 2, canary: sherpaOnnxOfflineCanaryModelConfig(encoder: find(dir, "encoder"), decoder: find(dir, "decoder"), srcLang: l, tgtLang: l))
    default:
      mc = sherpaOnnxOfflineModelConfig(tokens: tokens, numThreads: 2, moonshine: sherpaOnnxOfflineMoonshineModelConfig(encoder: find(dir, "encoder"), mergedDecoder: find(dir, "decoder")))
    }
    var cfg = sherpaOnnxOfflineRecognizerConfig(featConfig: sherpaOnnxFeatureConfig(), modelConfig: mc)
    return SherpaOnnxOfflineRecognizer(config: &cfg)
  }

  static func transcribe(_ info: ModelInfo, dir: URL, samples: [Float], lang: String) async throws -> [BolkitCore.Word] {
    let seconds = Double(samples.count) / 16_000
    return try await Task.detached {
      if info.stream {
        let r = online(dir, endpoints: false)
        for i in stride(from: 0, to: samples.count, by: 16_000) {
          r.acceptWaveform(samples: Array(samples[i..<min(i + 16_000, samples.count)]))
          while r.isReady() { r.decode() }
        }
        r.inputFinished()
        while r.isReady() { r.decode() }
        let res = r.getResult()
        return words(res.text, res.tokens, res.timestamps, seconds)
      }
      let res = offline(info, dir, lang: lang).decode(samples: samples)
      let p = res.result.pointee
      let tokens = (0..<Int(p.count)).compactMap { i in p.tokens_arr?[i].map { String(cString: $0) } }
      return words(res.text, tokens, res.timestamps, seconds)
    }.value
  }

  static func words(_ text: String, _ tokens: [String], _ times: [Float], _ seconds: Double) -> [BolkitCore.Word] {
    var out: [BolkitCore.Word] = []
    if !tokens.isEmpty, tokens.count == times.count {
      for (i, t) in tokens.enumerated() {
        let start = Double(times[i]), end = i + 1 < times.count ? Double(times[i + 1]) : start + 0.3
        if t.hasPrefix("▁") || t.hasPrefix(" ") || out.isEmpty {
          let w = t.replacingOccurrences(of: "▁", with: "").trimmingCharacters(in: .whitespaces)
          if !w.isEmpty { out.append(BolkitCore.Word(text: w, start: start, end: end)) }
        } else if let last = out.popLast() {
          out.append(BolkitCore.Word(text: last.text + t, start: last.start, end: end))
        }
      }
      return out
    }
    let ws = text.split(separator: " ").map(String.init)
    let step = seconds / Double(max(ws.count, 1))
    return ws.enumerated().map { BolkitCore.Word(text: $1, start: Double($0) * step, end: Double($0 + 1) * step) }
  }

  static func live(dir: URL, onText: @escaping @Sendable (String) -> Void) async -> LiveBackend {
    await Task.detached { SherpaLive(online(dir, endpoints: true), onText) }.value
  }
}

final class SherpaLive: LiveBackend, @unchecked Sendable {
  let rec: SherpaOnnxRecognizer
  let onText: @Sendable (String) -> Void
  let queue = DispatchQueue(label: "sherpa.live")
  var committed = ""

  init(_ rec: SherpaOnnxRecognizer, _ onText: @escaping @Sendable (String) -> Void) {
    self.rec = rec
    self.onText = onText
  }

  func joined(_ partial: String) -> String { [committed, partial].filter { !$0.isEmpty }.joined(separator: " ") }

  func accept(_ buffer: AVAudioPCMBuffer) {
    guard let ch = buffer.floatChannelData?[0] else { return }
    let s = Array(UnsafeBufferPointer(start: ch, count: Int(buffer.frameLength)))
    queue.async {
      self.rec.acceptWaveform(samples: s)
      while self.rec.isReady() { self.rec.decode() }
      let partial = self.rec.getResult().text.trimmingCharacters(in: .whitespacesAndNewlines)
      if self.rec.isEndpoint() {
        self.committed = self.joined(partial)
        self.rec.reset()
        self.onText(self.committed)
      } else {
        self.onText(self.joined(partial))
      }
    }
  }

  func finish() async -> String {
    await withCheckedContinuation { c in
      queue.async {
        self.rec.inputFinished()
        while self.rec.isReady() { self.rec.decode() }
        c.resume(returning: self.joined(self.rec.getResult().text.trimmingCharacters(in: .whitespacesAndNewlines)))
      }
    }
  }
}
