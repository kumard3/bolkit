import Foundation
import Testing
@testable import BolkitCore

@Test func decodesRNMeeting() throws {
  let json = #"{"id":"1-2","title":"M","createdAt":1791273917645,"durationSec":36,"language":"en","transcript":"hi","turns":[{"speaker":1,"text":"hi"}],"speakerNames":{"1":"Ann"},"hasAudio":true}"#
  let m = try JSONDecoder().decode(Meeting.self, from: Data(json.utf8))
  #expect(m.name(1) == "Ann" && m.name(0) == "Speaker 1" && m.speakers == [1])
}

@Test func turnsSplitOnPause() {
  let t = Digest.turns(from: [Word(text: "a", start: 0, end: 1), Word(text: "b", start: 1.1, end: 2), Word(text: "c", start: 5, end: 6)])
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

@Test func turnsFollowSpeakers() {
  let w = [Word(text: "hi", start: 0, end: 1), Word(text: "there", start: 1, end: 2), Word(text: "yo", start: 2.2, end: 3)]
  let t = Digest.turns(from: w, segments: [(0, 2, 0), (2, 3.5, 1)])
  #expect(t.map(\.speaker) == [0, 1] && t[0].text == "hi there")
}

@Test func parsesSections() {
  let s = Digest.sections("**Key points**\n- Ship Friday\n\n**Decisions**\n- Ship Friday\n**Suggestions**\nnone\n**Action items**\n- Maria: notes [00:12]")
  #expect(s["key points"] == ["Ship Friday"] && s["decisions"] == ["Ship Friday"] && s["suggestions"] == nil && s["action items"] == ["Maria: notes [00:12]"])
}

@Test func voiceCommands() {
  #expect(dictate("Hello there. New line. How are you", polish: false) == "Hello there.\nHow are you")
  #expect(dictate("buy milk scratch that buy eggs", polish: false) == "buy eggs")
  #expect(dictate("first draft delete everything I said so far. Final text", polish: false) == "Final text")
  #expect(dictate("one\ntwo\ndelete last line", polish: false) == "one")
  #expect(dictate("um i think so comma yes", polish: true) == "I think so, yes")
  #expect(dictate("bullet apples bullet pears", polish: false) == "• apples\n• pears")
}

func dictate(_ s: String, polish: Bool) -> String {
  let t = Polish.commands(Polish.edits(s))
  return polish ? Polish.polish(t) : t
}

@Test func smartCorrectionGuard() {
  #expect(Corrections.accept("let's meet at 2 actually 3 pm", "let's meet at 3 pm"))
  #expect(!Corrections.accept("I actually liked the demo", "I liked the demo"))
  #expect(!Corrections.accept("send it to Rahul no wait send it to Priya", "send it to Amit"))
}

@Test func hinglishCase() {
  #expect(Polish.hinglish("Dekhte hain ye nice leta Hai, ya kya leta Hai? Hai na.") == "Dekhte hain ye nice leta hai, ya kya leta hai? Hai na.")
}
