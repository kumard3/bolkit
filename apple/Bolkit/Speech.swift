import AVFoundation
import BolkitCore
import Speech

struct SpeechError: LocalizedError {
  let errorDescription: String?
  init(_ m: String) { errorDescription = m }
}

protocol LiveBackend: Sendable {
  func accept(_ buffer: AVAudioPCMBuffer)
  func finish() async -> String
}

enum Speech {
  static func authorize() async -> Bool {
    let mic = await AVAudioApplication.requestRecordPermission()
    let sp = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
    return mic && sp
  }

  static var micGranted: Bool { AVAudioApplication.shared.recordPermission == .granted }

  static func prepare(locale: String) async throws {
    if #available(iOS 26, *) { try await Modern.install(locale) }
  }

  static func words(file: URL, locale: String, vocab: [String]) async throws -> [Word] {
    if #available(iOS 26, *), SpeechTranscriber.isAvailable { return try await Modern.words(file, locale, vocab) }
    return try await Classic.words(file, locale)
  }

  static func live(locale: String, vocab: [String], onText: @escaping @Sendable (String) -> Void) async throws -> LiveBackend {
    if #available(iOS 26, *), SpeechTranscriber.isAvailable { return try await Modern.live(locale, vocab, onText) }
    return try Classic.live(locale, onText)
  }

  enum Classic {
    static func recognizer(_ id: String) throws -> SFSpeechRecognizer {
      guard let r = SFSpeechRecognizer(locale: Locale(identifier: id)), r.isAvailable else { throw SpeechError("Speech recognition is not available for \(id)") }
      return r
    }

    static func words(_ url: URL, _ locale: String) async throws -> [Word] {
      let r = try recognizer(locale)
      let req = SFSpeechURLRecognitionRequest(url: url)
      req.requiresOnDeviceRecognition = r.supportsOnDeviceRecognition
      return try await withCheckedThrowingContinuation { c in
        var done = false
        r.recognitionTask(with: req) { result, error in
          guard !done else { return }
          if let result, result.isFinal {
            done = true
            c.resume(returning: result.bestTranscription.segments.map { Word(text: $0.substring, start: $0.timestamp, end: $0.timestamp + $0.duration) })
          } else if let error {
            done = true
            c.resume(throwing: error)
          }
        }
      }
    }

    static func live(_ locale: String, _ onText: @escaping @Sendable (String) -> Void) throws -> LiveBackend {
      let r = try recognizer(locale)
      let req = SFSpeechAudioBufferRecognitionRequest()
      req.shouldReportPartialResults = true
      req.requiresOnDeviceRecognition = r.supportsOnDeviceRecognition
      return ClassicLive(recognizer: r, request: req, onText: onText)
    }
  }

  final class ClassicLive: LiveBackend, @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest
    let lock = NSLock()
    var text = ""
    var finished: CheckedContinuation<String, Never>?
    var isDone = false
    var task: SFSpeechRecognitionTask?

    init(recognizer: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest, onText: @escaping @Sendable (String) -> Void) {
      self.request = request
      task = recognizer.recognitionTask(with: request) { [weak self] result, error in
        guard let self else { return }
        if let result {
          let t = result.bestTranscription.formattedString
          self.lock.withLock { self.text = t }
          onText(t)
        }
        if result?.isFinal == true || error != nil { self.complete() }
      }
    }

    func complete() {
      lock.lock()
      isDone = true
      let c = finished
      finished = nil
      let t = text
      lock.unlock()
      c?.resume(returning: t)
    }

    func accept(_ buffer: AVAudioPCMBuffer) { request.append(buffer) }

    func finish() async -> String {
      request.endAudio()
      return await withCheckedContinuation { c in
        lock.lock()
        if isDone { let t = text; lock.unlock(); c.resume(returning: t) } else { finished = c; lock.unlock() }
      }
    }
  }

  @available(iOS 26, *)
  enum Modern {
    static func transcriber(_ id: String, live: Bool, timed: Bool) async throws -> SpeechTranscriber {
      guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: id)) else {
        throw SpeechError("\(id) is not available in Apple Speech")
      }
      return SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: live ? [.volatileResults] : [], attributeOptions: timed ? [.audioTimeRange] : [])
    }

    static func install(_ id: String) async throws {
      let t = try await transcriber(id, live: false, timed: false)
      if let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) { try await req.downloadAndInstall() }
    }

    static func words(_ url: URL, _ id: String, _ vocab: [String]) async throws -> [Word] {
      let t = try await transcriber(id, live: false, timed: true)
      if let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) { try await req.downloadAndInstall() }
      let analyzer = SpeechAnalyzer(modules: [t])
      let ctx = AnalysisContext()
      ctx.contextualStrings[.general] = vocab
      try await analyzer.setContext(ctx)
      let collect = Task { () -> [Word] in
        var out: [Word] = []
        for try await r in t.results {
          for run in r.text.runs {
            guard let range = run[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] else { continue }
            let s = String(r.text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { out.append(Word(text: s, start: range.start.seconds, end: range.end.seconds)) }
          }
        }
        return out
      }
      if let last = try await analyzer.analyzeSequence(from: try AVAudioFile(forReading: url)) {
        try await analyzer.finalizeAndFinish(through: last)
      } else {
        await analyzer.cancelAndFinishNow()
      }
      return try await collect.value
    }

    static func live(_ id: String, _ vocab: [String], _ onText: @escaping @Sendable (String) -> Void) async throws -> LiveBackend {
      let t = try await transcriber(id, live: true, timed: false)
      if let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) { try await req.downloadAndInstall() }
      guard let fmt = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [t]) else { throw SpeechError("Apple Speech assets are unavailable") }
      let analyzer = SpeechAnalyzer(modules: [t])
      let ctx = AnalysisContext()
      ctx.contextualStrings[.general] = vocab
      try await analyzer.setContext(ctx)
      try await analyzer.prepareToAnalyze(in: fmt)
      let s = ModernLive(t, analyzer, fmt, onText)
      s.start()
      return s
    }
  }

  @available(iOS 26, *)
  final class ModernLive: LiveBackend, @unchecked Sendable {
    let transcriber: SpeechTranscriber, analyzer: SpeechAnalyzer, resampler: Resampler
    let onText: @Sendable (String) -> Void
    let builder: AsyncStream<AnalyzerInput>.Continuation
    let stream: AsyncStream<AnalyzerInput>
    let lock = NSLock()
    var finalized: [String] = [], volatile = ""
    var results: Task<Void, Never>?
    var analysis: Task<CMTime?, Error>?

    init(_ t: SpeechTranscriber, _ a: SpeechAnalyzer, _ f: AVAudioFormat, _ onText: @escaping @Sendable (String) -> Void) {
      transcriber = t; analyzer = a; resampler = Resampler(to: f); self.onText = onText
      (stream, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)
    }

    func visible() -> String { lock.withLock { (finalized + (volatile.isEmpty ? [] : [volatile])).joined(separator: " ") } }

    func start() {
      results = Task { [self] in
        do {
          for try await r in transcriber.results {
            let s = String(r.text.characters)
            lock.withLock {
              if r.isFinal { if !s.isEmpty { finalized.append(s) }; volatile = "" } else { volatile = s }
            }
            onText(visible())
          }
        } catch {}
      }
      analysis = Task { [self] in try await analyzer.analyzeSequence(stream) }
    }

    func accept(_ buffer: AVAudioPCMBuffer) {
      if let b = resampler.convert(buffer) { builder.yield(AnalyzerInput(buffer: b)) }
    }

    func finish() async -> String {
      builder.finish()
      do {
        if let last = try await analysis?.value { try await analyzer.finalizeAndFinish(through: last) } else { await analyzer.cancelAndFinishNow() }
        await results?.value
      } catch { await analyzer.cancelAndFinishNow() }
      return visible()
    }
  }
}
