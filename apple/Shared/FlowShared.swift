import Foundation

enum FlowPhase: String, Codable { case off, idle, listening, working }

struct FlowState: Codable {
  var phase = FlowPhase.off
  var beat = Date.distantPast
  var resultID = ""
  var resultText = ""
  var resultAt = Date.distantPast
  var partial = ""
  var error: String?
  var alive: Bool { phase != .off && -beat.timeIntervalSinceNow < 6 }
}

struct FlowCommand: Codable {
  var action: String
  var at: Date
}

enum FlowShared {
  static let group = "group.ai.localvoice.app"
  static let command = "ai.localvoice.flow.command"
  static let changed = "ai.localvoice.flow.changed"
  static let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
  private static let stateURL = dir?.appendingPathComponent("flow.json")
  private static let commandURL = dir?.appendingPathComponent("command.json")
  static let wordsURL = dir?.appendingPathComponent("words.json")

  static func read() -> FlowState {
    stateURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(FlowState.self, from: $0) } ?? FlowState()
  }

  static func write(_ s: FlowState, notify: Bool) {
    if let stateURL, let d = try? JSONEncoder().encode(s) { try? d.write(to: stateURL, options: .atomic) }
    if notify { post(changed) }
  }

  static func send(_ action: String) {
    if let commandURL, let d = try? JSONEncoder().encode(FlowCommand(action: action, at: Date())) { try? d.write(to: commandURL, options: .atomic) }
    post(command)
  }

  static func take() -> String? {
    guard let commandURL, let d = try? Data(contentsOf: commandURL), let c = try? JSONDecoder().decode(FlowCommand.self, from: d), -c.at.timeIntervalSinceNow < 5 else { return nil }
    try? FileManager.default.removeItem(at: commandURL)
    return c.action
  }

  static func words() -> [String] {
    wordsURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
  }

  static func post(_ name: String) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
  }

  nonisolated(unsafe) fileprivate static var handlers: [String: () -> Void] = [:]

  static func observe(_ name: String, _ handler: @escaping () -> Void) {
    let first = handlers[name] == nil
    handlers[name] = handler
    guard first else { return }
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, n, _, _ in
      guard let key = n?.rawValue as String? else { return }
      DispatchQueue.main.async { FlowShared.handlers[key]?() }
    }, name as CFString, nil, .deliverImmediately)
  }
}
