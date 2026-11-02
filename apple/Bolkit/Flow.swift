import AVFoundation
import BolkitCore
import Foundation

final class Sink: @unchecked Sendable {
  private let lock = NSLock()
  private var live: LiveBackend?
  func set(_ l: LiveBackend?) { lock.withLock { live = l } }
  func accept(_ b: AVAudioPCMBuffer) { lock.withLock { live }?.accept(b) }
}

@MainActor @Observable
final class Flow {
  static let shared = Flow()
  static let idleSeconds = 300.0

  var hint = false
  private(set) var phase = FlowPhase.off
  @ObservationIgnored private weak var app: AppModel?
  @ObservationIgnored private let capture = Capture()
  @ObservationIgnored private let sink = Sink()
  @ObservationIgnored private var live: LiveBackend?
  @ObservationIgnored private var state = FlowState()
  @ObservationIgnored private var beat: Timer?
  @ObservationIgnored private var idle: Timer?

  func open(_ app: AppModel, listen: Bool) async {
    self.app = app
    FlowShared.observe(FlowShared.command) { [weak self] in
      guard let self, let a = FlowShared.take() else { return }
      Task { @MainActor in
        switch a {
        case "start": await self.listen()
        case "stop": await self.finish()
        default: self.end()
        }
      }
    }
    if phase == .off {
      guard await Speech.authorize() else { fail("Microphone or speech permission is off"); return }
      do {
        let sink = sink
        try capture.start(to: nil) { sink.accept($0) }
      } catch { fail(error.localizedDescription); return }
      beat = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
        MainActor.assumeIsolated { Flow.shared.tick() }
      }
      set(.idle)
    }
    if listen { await self.listen() }
  }

  func listen() async {
    guard phase == .idle, let app else { return }
    idle?.invalidate()
    state.error = nil
    do {
      let l = try await Speech.live(locale: app.language, vocab: app.vocab) { _ in }
      live = l
      sink.set(l)
      set(.listening)
    } catch {
      state.error = error.localizedDescription
      set(.idle)
    }
  }

  func finish() async {
    guard phase == .listening, let l = live, let app else { return }
    set(.working)
    sink.set(nil)
    live = nil
    let text = await app.clean(await l.finish().trimmingCharacters(in: .whitespacesAndNewlines))
    if !text.isEmpty { app.remember(text) }
    state.resultID = UUID().uuidString
    state.resultText = text
    state.resultAt = Date()
    set(.idle)
  }

  func end() {
    guard phase != .off else { return }
    sink.set(nil)
    if let l = live { Task { _ = await l.finish() } }
    live = nil
    capture.stop()
    beat?.invalidate()
    idle?.invalidate()
    set(.off)
  }

  private func tick() {
    if capture.state != .recording { end(); return }
    publish(notify: false)
  }

  private func fail(_ m: String) {
    state.error = m
    set(.off)
  }

  private func set(_ p: FlowPhase) {
    phase = p
    state.phase = p
    publish(notify: true)
    idle?.invalidate()
    if p == .idle {
      idle = Timer.scheduledTimer(withTimeInterval: Flow.idleSeconds, repeats: false) { _ in
        MainActor.assumeIsolated { Flow.shared.end() }
      }
    }
  }

  private func publish(notify: Bool) {
    state.beat = phase == .off ? .distantPast : Date()
    FlowShared.write(state, notify: notify)
  }

  static func publishWords(_ history: [HistoryItem], vocab: [String]) {
    var counts: [String: Int] = [:]
    for h in history.prefix(200) {
      for w in h.text.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" }) where w.count > 1 { counts[String(w), default: 0] += 1 }
    }
    let words = vocab.map { $0.lowercased() } + counts.sorted { $0.value > $1.value }.prefix(3000).map(\.key)
    if let url = FlowShared.wordsURL, let d = try? JSONEncoder().encode(words) { try? d.write(to: url, options: .atomic) }
  }
}
