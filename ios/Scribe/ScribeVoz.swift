import Foundation
import UIKit
import React
import Voz

@objc(ScribeVoz)
class ScribeVoz: RCTEventEmitter {
  private var hasListeners = false
  private var voz: Voz?

  override static func requiresMainQueueSetup() -> Bool { false }
  override func supportedEvents() -> [String]! { ["ScribeVoz"] }
  override func startObserving() { hasListeners = true }
  override func stopObserving() { hasListeners = false }

  private static var cacheRoot: String {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].path
  }

  private func ready(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> Voz {
    if let voz { return voz }
    let loaded = try await Voz(cacheRoot: Self.cacheRoot, progress: { progress($0.fraction) })
    voz = loaded
    return loaded
  }

  @objc(isDownloaded:rejecter:)
  func isDownloaded(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
    resolve(Voz.isDownloaded(cacheRoot: Self.cacheRoot))
  }

  @objc(download:rejecter:)
  func download(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
    Task {
      await MainActor.run { UIApplication.shared.isIdleTimerDisabled = true }
      defer { Task { @MainActor in UIApplication.shared.isIdleTimerDisabled = false } }
      do {
        var last = -1.0
        try await Voz.download(cacheRoot: Self.cacheRoot) { [weak self] p in
          guard let self, self.hasListeners, p.fraction - last >= 0.01 else { return }
          last = p.fraction
          self.sendEvent(withName: "ScribeVoz", body: ["type": "progress", "fraction": p.fraction])
        }
        var dir = URL(fileURLWithPath: Self.cacheRoot).appendingPathComponent("desert-ant-models", isDirectory: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        _ = try await self.ready()
        resolve(nil)
      } catch {
        reject("voz_download", error.localizedDescription, error)
      }
    }
  }

  @objc(remove:rejecter:)
  func remove(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
    voz = nil
    try? FileManager.default.removeItem(
      atPath: URL(fileURLWithPath: Self.cacheRoot).appendingPathComponent("desert-ant-models").path)
    resolve(nil)
  }

  @objc(transcribeFile:vocabulary:resolver:rejecter:)
  func transcribeFile(
    _ path: String, vocabulary: [String],
    resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    Task {
      do {
        let result = try await self.ready().transcribe(
          path: path.replacingOccurrences(of: "file://", with: ""), vocabulary: vocabulary)
        let units = result.words.map { ["text": $0.text.trimmingCharacters(in: .whitespaces), "start": $0.start, "end": $0.end] as [String: Any] }
        resolve(["text": result.text.trimmingCharacters(in: .whitespacesAndNewlines), "units": units,
                 "processingMs": result.processingTime * 1000])
      } catch {
        reject("voz_transcribe", error.localizedDescription, error)
      }
    }
  }
}
