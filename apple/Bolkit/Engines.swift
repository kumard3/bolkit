import AVFoundation
import BolkitCore
import SwiftUI

enum Kind { case apple, whisper, voz, parakeet, speakers, cloud }

struct ModelInfo: Identifiable {
  let id: String, title: String, note: String, kind: Kind
  var file: String? = nil, url: String? = nil, bytes: Int64 = 0, forced: String? = nil, sizeLabel: String
  var live: Bool { kind == .apple }
}

let catalog: [ModelInfo] = [
  .init(id: "system", title: "Apple Speech", note: "Built in. On device, live as you speak.", kind: .apple, sizeLabel: "Built in"),
  .init(id: "whisper:oriserve-swift-q8", title: "Hinglish Swift", note: "Whisper tuned for Hinglish and Indian English.", kind: .whisper,
        file: "ggml-oriserve-hinglish-q8_0.bin", url: "https://huggingface.co/anish2305/airnote-hinglish-stt-ggml/resolve/main/ggml-oriserve-hinglish-q8_0.bin", bytes: 81_768_585, forced: "hi", sizeLabel: "78 MB"),
  .init(id: "whisper:small-en-q5", title: "Whisper Small English", note: "Higher accuracy English.", kind: .whisper,
        file: "ggml-small.en-q5_1.bin", url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en-q5_1.bin", bytes: 190_098_681, sizeLabel: "181 MB"),
  .init(id: "voz", title: "Voz", note: "Powered by Desert Ant Labs. English, word timestamps.", kind: .voz, sizeLabel: "321 MB"),
  .init(id: "parakeet", title: "Parakeet", note: "NVIDIA Parakeet on the Neural Engine. English plus European languages.", kind: .parakeet, sizeLabel: "~460 MB"),
  .init(id: "sortformer", title: "Speaker labels", note: "NVIDIA Sortformer on the Neural Engine. Tells up to 4 speakers apart in meetings.", kind: .speakers, sizeLabel: "~120 MB"),
  .init(id: "cloud:azure", title: "Azure Speech", note: "MAI-Transcribe-2. Needs your Azure key.", kind: .cloud, sizeLabel: "Cloud"),
  .init(id: "cloud:azureopenai", title: "Azure OpenAI", note: "Your transcription deployment. Needs endpoint and key.", kind: .cloud, sizeLabel: "Cloud"),
  .init(id: "cloud:openai", title: "OpenAI compatible", note: "Any /audio/transcriptions endpoint. Needs your key.", kind: .cloud, sizeLabel: "Cloud"),
]

func modelInfo(_ id: String) -> ModelInfo { catalog.first { $0.id == id } ?? catalog[0] }

enum Audio {
  static func samples(_ url: URL) throws -> [Float] {
    let f = try AVAudioFile(forReading: url)
    guard let buf = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)) else { return [] }
    try f.read(into: buf)
    guard let out = Resampler(to: Capture.format).convert(buf), let ch = out.floatChannelData?[0] else { return [] }
    return Array(UnsafeBufferPointer(start: ch, count: Int(out.frameLength)))
  }
}

@MainActor @Observable
final class ModelStore {
  var progress: [String: Double] = [:]
  var failure: [String: String] = [:]
  var installedTick = 0
  let dir = URL.documentsDirectory.appendingPathComponent("models", isDirectory: true)
  let store = Store()

  func installed(_ m: ModelInfo) -> Bool {
    _ = installedTick
    switch m.kind {
    case .apple: return true
    case .cloud: return Cloud.ready(m.id, store.settings())
    case .whisper:
      let size = (try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(m.file!).path)[.size] as? Int64) ?? 0
      return size == m.bytes
    case .voz: return Extra.vozInstalled()
    case .parakeet: return Extra.parakeetInstalled()
    case .speakers: return Extra.sortformerInstalled()
    }
  }

  func url(_ m: ModelInfo) -> URL { dir.appendingPathComponent(m.file ?? m.id) }

  func download(_ m: ModelInfo) async {
    failure[m.id] = nil
    progress[m.id] = 0
    do {
      switch m.kind {
      case .whisper: try await fetch(m)
      case .voz: try await Extra.vozDownload { p in Task { @MainActor in self.progress[m.id] = p } }
      case .parakeet: try await Extra.parakeetDownload { p in Task { @MainActor in self.progress[m.id] = p } }
      case .speakers: try await Extra.sortformerDownload { p in Task { @MainActor in self.progress[m.id] = p } }
      default: break
      }
    } catch { failure[m.id] = error.localizedDescription }
    progress[m.id] = nil
    installedTick += 1
  }

  func delete(_ m: ModelInfo) {
    switch m.kind {
    case .whisper: try? FileManager.default.removeItem(at: url(m))
    case .voz: Extra.vozDelete()
    case .parakeet: Extra.parakeetDelete()
    case .speakers: Extra.sortformerDelete()
    default: break
    }
    installedTick += 1
  }

  private func fetch(_ m: ModelInfo) async throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let dest = url(m)
    var obs: NSKeyValueObservation?
    defer { obs?.invalidate() }
    let tmp: URL = try await withCheckedThrowingContinuation { c in
      let t = URLSession.shared.downloadTask(with: URL(string: m.url!)!) { u, _, e in
        if let u {
          let keep = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
          try? FileManager.default.moveItem(at: u, to: keep)
          c.resume(returning: keep)
        } else { c.resume(throwing: e ?? SpeechError("Download failed")) }
      }
      obs = t.progress.observe(\.fractionCompleted) { p, _ in Task { @MainActor in self.progress[m.id] = p.fractionCompleted } }
      t.resume()
    }
    try? FileManager.default.removeItem(at: dest)
    try FileManager.default.moveItem(at: tmp, to: dest)
    let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
    if size != m.bytes { try? FileManager.default.removeItem(at: dest); throw SpeechError("Download was incomplete. Try again.") }
  }
}
