import Foundation
import whisper

public final class WhisperEngine: @unchecked Sendable {
  private var ctx: OpaquePointer?
  private var path = ""
  private let lock = NSLock()

  public init() {}
  deinit { if let ctx { whisper_free(ctx) } }

  public func transcribe(samples: [Float], model: URL, language: String) throws -> [Word] {
    lock.lock()
    defer { lock.unlock() }
    if ctx == nil || path != model.path {
      if let ctx { whisper_free(ctx) }
      ctx = whisper_init_from_file_with_params(model.path, whisper_context_default_params())
      path = model.path
    }
    guard let ctx else { throw NSError(domain: "Whisper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not load \(model.lastPathComponent)"]) }
    var p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
    p.n_threads = 4
    p.print_progress = false; p.print_realtime = false; p.print_timestamps = false; p.print_special = false
    p.translate = false
    p.initial_prompt = nil
    let rc = language.withCString { lang -> Int32 in
      p.language = lang
      return whisper_full(ctx, p, samples, Int32(samples.count))
    }
    guard rc == 0 else { throw NSError(domain: "Whisper", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: "Whisper failed (\(rc))"]) }
    var out: [Word] = []
    for i in 0..<Int(whisper_full_n_segments(ctx)) {
      let text = String(cString: whisper_full_get_segment_text(ctx, Int32(i))).trimmingCharacters(in: .whitespacesAndNewlines)
      let t0 = Double(whisper_full_get_segment_t0(ctx, Int32(i))) / 100, t1 = Double(whisper_full_get_segment_t1(ctx, Int32(i))) / 100
      let ws = text.split(separator: " ")
      guard !ws.isEmpty else { continue }
      let step = (t1 - t0) / Double(ws.count)
      for (k, w) in ws.enumerated() { out.append(Word(text: String(w), start: t0 + step * Double(k), end: t0 + step * Double(k + 1))) }
    }
    return out
  }
}
