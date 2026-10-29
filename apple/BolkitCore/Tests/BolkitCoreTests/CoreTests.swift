import Foundation
import Testing
@testable import BolkitCore

@Test func decodesRNMeeting() throws {
  let json = #"{"id":"1-2","title":"M","createdAt":1791273917645,"durationSec":36,"language":"en","transcript":"hi","turns":[{"speaker":1,"text":"hi"}],"speakerNames":{"1":"Ann"},"hasAudio":true}"#
  let m = try JSONDecoder().decode(Meeting.self, from: Data(json.utf8))
  #expect(m.name(1) == "Ann" && m.name(0) == "Speaker 1" && m.speakers == [1])
}

@Test func turnsSplitOnPause() {
  let t = Digest.turns(from: [("a", 0, 1), ("b", 1.1, 2), ("c", 5, 6)])
  #expect(t.map(\.text) == ["a b", "c"])
}

@Test func storeRoundTripKeepsUnknownSettings() throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  try Data(#"{"cloudBaseUrl":"x","onboarded":true}"#.utf8).write(to: dir.appendingPathComponent("settings.json"))
  var s = Store(root: dir).settings()
  s.set("yourName", "Kumar")
  let again = Store(root: dir).settings()
  #expect(again.string("cloudBaseUrl") == "x" && again.string("yourName") == "Kumar" && again.bool("onboarded"))
}
