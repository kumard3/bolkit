import AVFoundation
import BolkitCore
import SwiftUI

let languages: [(code: String, name: String)] = [
  ("en-US", "English (US)"), ("en-IN", "English (India)"), ("en-GB", "English (UK)"), ("hi-IN", "Hinglish"),
  ("es-ES", "Spanish"), ("fr-FR", "French"), ("de-DE", "German"), ("pt-BR", "Portuguese"), ("it-IT", "Italian"), ("ja-JP", "Japanese"),
]

let targets: [(code: String, name: String)] = [
  ("en", "English"), ("hi", "Hindi"), ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("pt-BR", "Portuguese"),
  ("it", "Italian"), ("ja", "Japanese"), ("ko", "Korean"), ("zh-Hans", "Chinese"), ("ar", "Arabic"), ("ru", "Russian"),
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
  var dictID: String?
  var showHistory = false
  var translateTick = 0
  var dictating = false
  var copyOnFinish = false
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
  var translateTarget: String { get { settings.string("translateTarget") } set { settings.set("translateTarget", newValue) } }
  var smartCorrections: Bool { get { settings.bool("smartCorrections", true) } set { settings.set("smartCorrections", newValue) } }
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
    guard info.kind != .apple, models.installed(info) else {
      return try await Speech.words(file: file, locale: language, vocab: vocab)
    }
    switch info.kind {
    case .whisper:
      let samples = try Audio.samples(file)
      let url = models.url(info), lang = info.forced ?? shortLang, w = whisper
      return try await Task.detached { try w.transcribe(samples: samples, model: url, language: lang) }.value
    case .cloud:
      return try await Cloud.transcribe(info.id, file: file, settings: store.settings(), language: language, vocab: vocab)
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
    t = Polish.edits(t)
    if smartCorrections { t = await Brain.correct(t) }
    t = Polish.commands(t)
    if language == "hi-IN" { t = Polish.hinglish(t) }
    if autoPolish { t = Polish.polish(t) }
    dictText = t
    dictID = nil
    guard !t.isEmpty else { return }
    if copyOnFinish {
      copyOnFinish = false
      UIPasteboard.general.string = t
    }
    let item = HistoryItem(text: t, language: shortLang)
    dictID = item.id
    history.insert(item, at: 0)
    store.saveHistory(history)
    if !translateTarget.isEmpty { translateTick += 1 }
  }

  func saveTranslation(_ text: String, to code: String) {
    var item = HistoryItem(text: text, language: code)
    item.translated = true
    item.translatedTo = code
    history.insert(item, at: 0)
    store.saveHistory(history)
    open(item)
  }

  func polishDictation() async {
    setDictText(await Brain.polish(dictText, vocab: vocab) ?? Polish.polish(dictText))
  }

  func summarizeDictation() async {
    let s = await Brain.summarize(dictText) ?? Digest.summary(dictText)
    guard !s.isEmpty else { return }
    let item = HistoryItem(text: s, language: shortLang)
    history.insert(item, at: 0)
    store.saveHistory(history)
    open(item)
  }

  func setDictText(_ t: String) {
    dictText = t
    guard let id = dictID, let i = history.firstIndex(where: { $0.id == id }) else { return }
    history[i].text = t
    store.saveHistory(history)
  }

  func open(_ h: HistoryItem) {
    dictText = h.text
    dictID = h.id
  }

  func deleteHistory(_ id: String) {
    history.removeAll { $0.id == id }
    if dictID == id { dictID = nil }
    store.saveHistory(history)
  }

  func clearHistory() {
    history = []
    dictID = nil
    store.saveHistory([])
  }

  var canDeleteAll: Bool { !dictating && !busy && recordingID == nil }

  func deleteAll() {
    guard canDeleteAll else { return }
    Task { await Engines.shared.dropVoz(); await Engines.shared.dropParakeet() }
    let fm = FileManager.default
    for dir in [URL.documentsDirectory, URL.applicationSupportDirectory] {
      for u in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] { try? fm.removeItem(at: u) }
    }
    for k in ["openai", "azureSpeech", "azureOpenAI"] { Keychain.set(k, "") }
    settings = store.settings()
    dictText = ""
    dictID = nil
    models.installedTick += 1
    reload()
  }

  func importAudio(_ src: URL) async {
    error = nil
    let id = Store.newID(), dst = store.audioURL(id)
    let scoped = src.startAccessingSecurityScopedResource()
    defer { if scoped { src.stopAccessingSecurityScopedResource() } }
    busy = true
    do {
      try FileManager.default.createDirectory(at: store.dir(id), withIntermediateDirectories: true)
      let dur = try await Task.detached { try Audio.convert(src, to: dst) }.value
      await finishMeeting(id, duration: dur, title: src.deletingPathExtension().lastPathComponent)
      openID = id
      tab = 2
    } catch {
      store.delete(id)
      busy = false
      self.error = "Could not import that file. \(error.localizedDescription)"
    }
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
    await finishMeeting(id, duration: dur)
    openID = id
    tab = 2
  }

  func finishMeeting(_ id: String, duration dur: Double, title: String? = nil) async {
    busy = true
    defer { busy = false }
    var turns: [Turn] = []
    do {
      let words = try await transcribe(store.audioURL(id), model: meetingModel)
      var segs: [(start: Double, end: Double, speaker: Int)] = []
      let sf = modelInfo("sortformer")
      if settings.bool("diarizationEnabled", true), models.installed(sf) {
        let samples = try Audio.samples(store.audioURL(id))
        segs = ((try? await Engines.shared.diarize(samples)) ?? []).map { ($0.start, $0.end, $0.speaker) }
      }
      turns = Digest.turns(from: words, segments: segs)
      if language == "hi-IN" { turns = turns.map { var t = $0; t.text = Polish.hinglish(t.text); return t } }
      if autoPolish { turns = turns.map { var t = $0; t.text = Polish.polish(t.text); return t } }
    } catch { self.error = "Saved the audio, but transcription failed: \(error.localizedDescription)" }
    let text = turns.map(\.text).joined(separator: " ")
    let created = Double(id.split(separator: "-").first.flatMap { Int($0) } ?? Int(Date().timeIntervalSince1970 * 1000))
    var m = Meeting(id: id, title: title ?? Meeting.defaultTitle(Date(timeIntervalSince1970: created / 1000)), createdAt: created, durationSec: dur.rounded(), language: shortLang, transcript: text, turns: turns, hasAudio: true)
    if !text.isEmpty { m.summary = Digest.summary(text); m.decisions = Digest.decisions(text) }
    if let n = yourName.nilIfEmpty, m.turns?.isEmpty == false { m.speakerNames = ["0": n] }
    await Brain.enrich(&m, vocab: vocab, you: yourName)
    try? store.save(m)
    reload()
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
    for name in (UserDefaults.standard.string(forKey: "selfInstall") ?? "").split(separator: ",") {
      let info = modelInfo(String(name))
      if !models.installed(info) { await models.download(info); out["install_\(info.id)"] = models.failure[info.id] ?? "ok" }
    }
    var engines: [String: Any] = [:]
    for info in catalog where ![.apple, .speakers].contains(info.kind) && models.installed(info) {
      let t = Date()
      do {
        let words = try await transcribe(wav, model: info.id)
        engines[info.id] = ["text": words.map(\.text).joined(separator: " "), "seconds": Date().timeIntervalSince(t), "words": words.count]
      } catch { engines[info.id] = ["error": error.localizedDescription] }
    }
    out["engines"] = engines
    let id = Store.newID()
    try? FileManager.default.createDirectory(at: store.dir(id), withIntermediateDirectories: true)
    try? FileManager.default.copyItem(at: FileManager.default.fileExists(atPath: dir.appendingPathComponent("selftest2.wav").path) ? dir.appendingPathComponent("selftest2.wav") : wav, to: store.audioURL(id))
    let t1 = Date()
    await finishMeeting(id, duration: 14)
    if let m = meetings.first(where: { $0.id == id }) {
      out["meeting"] = ["seconds": Date().timeIntervalSince(t1), "speakers": m.speakers, "turns": (m.turns ?? []).map { ["speaker": $0.speaker, "start": $0.start ?? 0, "text": $0.text] }, "summary": m.summary ?? "", "decisions": m.decisions ?? [], "suggestions": m.suggestions ?? [], "actions": m.actions ?? [], "title": m.title, "brain": Brain.available, "chapters": (m.chapters ?? []).map(\.title)]
    }
    store.delete(id)
    reload()
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
