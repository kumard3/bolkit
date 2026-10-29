import Foundation
import Security

public struct Store: Sendable {
  public let root: URL
  public init(root: URL = URL.documentsDirectory) { self.root = root }

  var meetingsDir: URL { root.appendingPathComponent("meetings", isDirectory: true) }
  public func dir(_ id: String) -> URL { meetingsDir.appendingPathComponent(id, isDirectory: true) }
  public func audioURL(_ id: String) -> URL { dir(id).appendingPathComponent("audio.wav") }

  public func meetings() -> [Meeting] {
    let ids = (try? FileManager.default.contentsOfDirectory(atPath: meetingsDir.path)) ?? []
    return ids.compactMap { id in
      (try? Data(contentsOf: dir(id).appendingPathComponent("meeting.json")))
        .flatMap { try? JSONDecoder().decode(Meeting.self, from: $0) }
    }.sorted { $0.createdAt > $1.createdAt }
  }

  public func save(_ m: Meeting) throws {
    try FileManager.default.createDirectory(at: dir(m.id), withIntermediateDirectories: true)
    let enc = JSONEncoder()
    enc.outputFormatting = [.withoutEscapingSlashes]
    try enc.encode(m).write(to: dir(m.id).appendingPathComponent("meeting.json"), options: .atomic)
  }

  public func delete(_ id: String) { try? FileManager.default.removeItem(at: dir(id)) }

  public static func newID() -> String {
    "\(Int(Date().timeIntervalSince1970 * 1000))-\(Int.random(in: 0..<1_000_000))"
  }

  var historyURL: URL { root.appendingPathComponent("history.json") }

  public func history() -> [HistoryItem] {
    (try? Data(contentsOf: historyURL)).flatMap { try? JSONDecoder().decode([HistoryItem].self, from: $0) } ?? []
  }

  public func saveHistory(_ items: [HistoryItem]) {
    try? JSONEncoder().encode(Array(items.prefix(200))).write(to: historyURL, options: .atomic)
  }

  public func settings() -> Settings { Settings(url: root.appendingPathComponent("settings.json")) }
}

/// Reads and writes the RN settings.json as a raw dictionary so keys this app does not know survive a round trip.
public struct Settings: Sendable {
  let url: URL
  var raw: [String: any Sendable]

  init(url: URL) {
    self.url = url
    raw = (try? Data(contentsOf: url))
      .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: any Sendable] } ?? [:]
  }

  public func string(_ k: String, _ d: String = "") -> String { raw[k] as? String ?? d }
  public func bool(_ k: String, _ d: Bool = false) -> Bool { raw[k] as? Bool ?? d }
  public func list(_ k: String) -> [String] { raw[k] as? [String] ?? [] }

  public mutating func set(_ k: String, _ v: any Sendable) {
    raw[k] = v
    if let data = try? JSONSerialization.data(withJSONObject: raw) { try? data.write(to: url, options: .atomic) }
  }
}

public enum Keychain {
  static let service = "ai.localvoice.native.keys"

  public static func get(_ account: String) -> String {
    var out: CFTypeRef?
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                            kSecAttrAccount as String: account, kSecReturnData as String: true]
    guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return "" }
    return String(decoding: d, as: UTF8.self)
  }

  public static func set(_ account: String, _ value: String) {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                            kSecAttrAccount as String: account]
    SecItemDelete(q as CFDictionary)
    guard !value.isEmpty else { return }
    SecItemAdd(q.merging([kSecValueData as String: Data(value.utf8)]) { $1 } as CFDictionary, nil)
  }
}
