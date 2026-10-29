import AVFoundation
import BolkitCore
import SwiftUI

let languages: [(code: String, name: String)] = [
  ("en-US", "English (US)"), ("en-IN", "English (India)"), ("en-GB", "English (UK)"), ("hi-IN", "Hindi"),
  ("es-ES", "Spanish"), ("fr-FR", "French"), ("de-DE", "German"), ("pt-BR", "Portuguese"), ("it-IT", "Italian"), ("ja-JP", "Japanese"),
]

@MainActor @Observable
final class AppModel {
  let store = Store()
  var settings: Settings
  var meetings: [Meeting] = []
  var history: [HistoryItem] = []
  let capture = Capture()
  let models = ModelStore()
  @ObservationIgnored let whisper = WhisperEngine()

  var dictText = ""
  var dictating = false
  var busy = false
  var error: String?
  var recordingID: String?
  var openID: String?
  var tab = 0
  @ObservationIgnored var liveSession: LiveBackend?

  init() {
    settings = store.settings()
    reload()
    let id = settings.string("cloudApiKey")
    if !id.isEmpty {
      Keychain.set("openai", id)
      settings.set("cloudApiKey", "")
    }
  }

  func reload() {
    meetings = store.meetings()
    history = store.history()
  }

  var language: String { get { settings.string("language", "en-US") } set { settings.set("language", newValue) } }
  var yourName: String { get { settings.string("yourName") } set { settings.set("yourName", newValue) } }
  var autoPolish: Bool { get { settings.bool("autoPolish") } set { settings.set("autoPolish", newValue) } }
  var onboarded: Bool { get { settings.bool("onboarded") } set { settings.set("onboarded", newValue) } }
  var dictationModel: String { get { settings.string("selectedModelId", "system") } set { settings.set("selectedModelId", newValue) } }
  var meetingModel: String { get { settings.string("recordModelId", "system").ifEmpty("system") } set { settings.set("recordModelId", newValue) } }
  var vocab: [String] { get { settings.list("vocab") } set { settings.set("vocab", newValue) } }
  var cloudProvider: String { get { settings.string("cloudProvider", "openai") } set { settings.set("cloudProvider", newValue) } }
  func text(_ k: String) -> String { settings.string(k) }
  func setText(_ k: String, _ v: String) { settings.set(k, v) }

  var shortLang: String { String(language.prefix(2)) }

  func transcribe(_ file: URL, model id: String) async throws -> [Word] {
    let info = modelInfo(id)
    guard info.kind != .apple, models.installed(info) || info.kind == .cloud else {
      return try await Speech.words(file: file, locale: language, vocab: vocab)
    }
    switch info.kind {
    case .whisper:
      let samples = try Audio.samples(file)
      let url = models.url(info), lang = info.forced ?? shortLang, w = whisper
      return try await Task.detached { try w.transcribe(samples: samples, model: url, language: lang) }.value
    default:
      return try await Extra.transcribe(info, file: file, app: self)
    }
  }

  func toggleDictate() async {
    error = nil
    if dictating { await finishDictation(); return }
    guard await Speech.authorize() else { error = "Microphone or speech permission is off. Turn it on in Settings."; return }
    do {
      dictText = ""
      let info = modelInfo(dictationModel)
      if !info.live && models.installed(info) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dictation.wav")
        try capture.start(to: url)
        dictating = true
        return
      }
      let live = try await Speech.live(locale: language, vocab: vocab) { [weak self] t in Task { @MainActor in self?.dictText = t } }
      liveSession = live
      try capture.start(to: nil) { live.accept($0) }
      dictating = true
    } catch { self.error = error.localizedDescription }
  }

  func finishDictation() async {
    capture.stop()
    dictating = false
    var t: String
    if let live = liveSession {
      liveSession = nil
      t = await live.finish().trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
      busy = true
      defer { busy = false }
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("dictation.wav")
      do { t = try await transcribe(url, model: dictationModel).map(\.text).joined(separator: " ") } catch { self.error = error.localizedDescription; return }
    }
    if autoPolish { t = polish(t) }
    dictText = t
    guard !t.isEmpty else { return }
    history.insert(HistoryItem(text: t, language: shortLang), at: 0)
    store.saveHistory(history)
  }

  func polish(_ s: String) -> String {
    guard let f = s.first else { return s }
    let t = f.uppercased() + s.dropFirst()
    return t.last.map { ".!?".contains($0) } == true ? t : t + "."
  }

  func deleteHistory(_ id: String) {
    history.removeAll { $0.id == id }
    store.saveHistory(history)
  }

  func startRecording() async {
    error = nil
    guard await Speech.authorize() else { error = "Microphone or speech permission is off. Turn it on in Settings."; return }
    let id = Store.newID()
    do {
      try FileManager.default.createDirectory(at: store.dir(id), withIntermediateDirectories: true)
      try capture.start(to: store.audioURL(id))
      recordingID = id
    } catch { self.error = error.localizedDescription }
  }

  func stopRecording() async {
    guard let id = recordingID else { return }
    let dur = capture.stop()
    recordingID = nil
    busy = true
    defer { busy = false }
    var turns: [Turn] = []
    do {
      let words = try await transcribe(store.audioURL(id), model: meetingModel)
      turns = Digest.turns(from: words.map { ($0.text, $0.start, $0.end) })
    } catch { self.error = "Saved the audio, but transcription failed: \(error.localizedDescription)" }
    let text = turns.map(\.text).joined(separator: " ")
    let created = Double(id.split(separator: "-").first.flatMap { Int($0) } ?? Int(Date().timeIntervalSince1970 * 1000))
    var m = Meeting(id: id, title: Meeting.defaultTitle(Date(timeIntervalSince1970: created / 1000)), createdAt: created, durationSec: dur.rounded(), language: shortLang, transcript: text, turns: turns, hasAudio: true)
    if !text.isEmpty { m.summary = Digest.summary(text); m.decisions = Digest.decisions(text) }
    if let n = yourName.nilIfEmpty, m.turns?.isEmpty == false { m.speakerNames = ["0": n] }
    try? store.save(m)
    reload()
    openID = id
    tab = 2
  }

  func update(_ m: Meeting) {
    try? store.save(m)
    reload()
  }

  func delete(_ id: String) {
    store.delete(id)
    reload()
  }

  func runSelfTest() async {
    let dir = URL.documentsDirectory
    let wav = dir.appendingPathComponent("selftest.wav")
    guard FileManager.default.fileExists(atPath: wav.path) else { return }
    var out: [String: Any] = ["os": ProcessInfo.processInfo.operatingSystemVersionString, "ran": Date().timeIntervalSince1970]
    let t0 = Date()
    do {
      let words = try await Speech.words(file: wav, locale: language, vocab: [])
      out["fileText"] = words.map(\.text).joined(separator: " ")
      out["fileWords"] = words.count
      out["fileSeconds"] = Date().timeIntervalSince(t0)
    } catch { out["fileError"] = error.localizedDescription }
    do {
      let last = Box<String>("")
      let live = try await Speech.live(locale: language, vocab: []) { last.value = $0 }
      let f = try AVAudioFile(forReading: wav)
      while f.framePosition < f.length {
        guard let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: 4096) else { break }
        try f.read(into: b)
        live.accept(b)
      }
      out["liveText"] = await live.finish()
      out["partial"] = last.value
    } catch { out["liveError"] = error.localizedDescription }
    var engines: [String: Any] = [:]
    for info in catalog where info.kind != .apple && (models.installed(info) || info.kind == .cloud) {
      let t = Date()
      do {
        let words = try await transcribe(wav, model: info.id)
        engines[info.id] = ["text": words.map(\.text).joined(separator: " "), "seconds": Date().timeIntervalSince(t), "words": words.count]
      } catch { engines[info.id] = ["error": error.localizedDescription] }
    }
    out["engines"] = engines
    try? JSONSerialization.data(withJSONObject: out, options: .prettyPrinted).write(to: dir.appendingPathComponent("selftest.json"))
    print("SELFTEST", out)
  }
}

final class Box<T>: @unchecked Sendable {
  var value: T
  init(_ v: T) { value = v }
}

extension String {
  func ifEmpty(_ d: String) -> String { isEmpty ? d : self }
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
