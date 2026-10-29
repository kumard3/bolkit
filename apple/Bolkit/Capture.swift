import AVFoundation

final class Resampler: @unchecked Sendable {
  private let target: AVAudioFormat
  private var converter: AVAudioConverter?
  private var source: AVAudioFormat?
  init(to target: AVAudioFormat) { self.target = target }

  func convert(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    if input.format == target { return input }
    if source != input.format || converter == nil {
      converter = AVAudioConverter(from: input.format, to: target)
      source = input.format
    }
    guard let converter else { return nil }
    let cap = AVAudioFrameCount(ceil(Double(input.frameLength) * target.sampleRate / max(input.format.sampleRate, 1))) + 32
    guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap) else { return nil }
    var fed = false
    var err: NSError?
    converter.convert(to: out, error: &err) { _, status in
      if fed { status.pointee = .noDataNow; return nil }
      fed = true; status.pointee = .haveData; return input
    }
    return err == nil && out.frameLength > 0 ? out : nil
  }
}

@MainActor @Observable
final class Capture {
  enum State { case idle, recording, paused, interrupted }
  private(set) var state = State.idle
  private(set) var seconds = 0.0
  private(set) var levels: [Float] = []

  nonisolated static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
  @ObservationIgnored private let engine = AVAudioEngine()
  @ObservationIgnored private let box = Box()
  @ObservationIgnored private var observers: [NSObjectProtocol] = []

  final class Box: @unchecked Sendable {
    let lock = NSLock()
    var file: AVAudioFile?
    var frames: AVAudioFramePosition = 0
    var resampler = Resampler(to: Capture.format)
    var live = false
    var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
    var level: Float = 0
  }

  func start(to url: URL?, onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)? = nil) throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
    try session.setActive(true)
    box.lock.withLock {
      box.file = url.flatMap {
        try? AVAudioFile(forWriting: $0, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false], commonFormat: .pcmFormatFloat32, interleaved: false)
      }
      box.frames = 0
      box.live = true
      box.onBuffer = onBuffer
    }
    seconds = 0; levels = []
    try startEngine()
    state = .recording
    observe()
    Task { await tick() }
  }

  private func startEngine() throws {
    let input = engine.inputNode
    input.removeTap(onBus: 0)
    box.lock.withLock { box.resampler = Resampler(to: Capture.format) }
    let box = self.box
    input.installTap(onBus: 0, bufferSize: 2048, format: input.outputFormat(forBus: 0)) { buf, _ in
      box.lock.lock()
      defer { box.lock.unlock() }
      guard box.live, let out = box.resampler.convert(buf), let ch = out.floatChannelData?[0] else { return }
      try? box.file?.write(from: out)
      box.frames += AVAudioFramePosition(out.frameLength)
      var sum: Float = 0
      for i in 0..<Int(out.frameLength) { sum += ch[i] * ch[i] }
      box.level = min(1, (sum / Float(max(1, out.frameLength))).squareRoot() * 6)
      box.onBuffer?(out)
    }
    engine.prepare()
    try engine.start()
  }

  private func tick() async {
    while state != .idle {
      try? await Task.sleep(for: .milliseconds(80))
      let (frames, level) = box.lock.withLock { (box.frames, box.level) }
      seconds = Double(frames) / 16000
      if state == .recording { levels.append(level); if levels.count > 200 { levels.removeFirst(100) } }
    }
  }

  func pause() {
    guard state == .recording else { return }
    box.lock.withLock { box.live = false }
    engine.pause()
    state = .paused
  }

  func resume() {
    guard state == .paused || state == .interrupted else { return }
    box.lock.withLock { box.live = true }
    do {
      try AVAudioSession.sharedInstance().setActive(true)
      try startEngine()
      state = .recording
    } catch { state = .interrupted }
  }

  @discardableResult
  func stop() -> Double {
    box.lock.withLock { box.live = false; box.file = nil; box.onBuffer = nil }
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    observers.forEach(NotificationCenter.default.removeObserver)
    observers = []
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    state = .idle
    return seconds
  }

  private func observe() {
    let nc = NotificationCenter.default
    observers = [
      nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
        let type = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
        let opts = AVAudioSession.InterruptionOptions(rawValue: n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
        MainActor.assumeIsolated {
          guard let self, self.state != .idle else { return }
          if type == .began, self.state == .recording {
            self.box.lock.withLock { self.box.live = false }
            self.state = .interrupted
          } else if type == .ended, self.state == .interrupted, opts.contains(.shouldResume) {
            self.resume()
          }
        }
      },
      nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self, self.state == .recording else { return }
          do { try self.startEngine() } catch { self.state = .interrupted }
        }
      },
    ]
  }
}
