import BolkitCore
import Foundation

enum Extra {
  static func vozInstalled() -> Bool { false }
  static func vozDownload(_ p: @escaping @Sendable (Double) -> Void) async throws {}
  static func vozDelete() {}
  static func parakeetInstalled() -> Bool { false }
  static func parakeetDownload(_ p: @escaping @Sendable (Double) -> Void) async throws {}
  static func parakeetDelete() {}
  @MainActor static func transcribe(_ info: ModelInfo, file: URL, app: AppModel) async throws -> [Word] { throw SpeechError("\(info.title) is not available yet") }
}
