import AVFoundation
import BolkitCore
import SwiftUI

struct MeetingsView: View {
  @Environment(AppModel.self) var m
  @State private var query = ""

  var shown: [Meeting] {
    let q = query.lowercased()
    return q.isEmpty ? m.meetings : m.meetings.filter { $0.title.lowercased().contains(q) || $0.transcript.lowercased().contains(q) || $0.id.contains(q) }
  }

  var body: some View {
    @Bindable var m = m
    List {
      if shown.isEmpty { Text(m.meetings.isEmpty ? "No meetings yet. Record one." : "No matches.").foregroundStyle(Mono.dim).listRowBackground(Color.clear) }
      ForEach(shown) { x in
        NavigationLink(value: x.id) {
          VStack(alignment: .leading, spacing: 4) {
            Text(x.title).foregroundStyle(.white)
            Text(x.summary ?? x.transcript).font(.footnote).foregroundStyle(Mono.dim).lineLimit(2)
            Text("\(x.date.formatted(date: .abbreviated, time: .shortened))  \(durationLabel(x.durationSec))").font(.caption).foregroundStyle(Mono.faint)
          }
        }
        .listRowBackground(Mono.surface)
        .swipeActions { Button("Delete", role: .destructive) { m.delete(x.id) } }
      }
    }
    .scrollContentBackground(.hidden)
    .background(Mono.bg.ignoresSafeArea())
    .navigationTitle("Meetings")
    .searchable(text: $query, prompt: "Search meetings")
    .navigationDestination(for: String.self) { MeetingDetail(id: $0) }
    .navigationDestination(item: $m.openID) { MeetingDetail(id: $0) }
  }
}

@MainActor @Observable
final class Player: NSObject, AVAudioPlayerDelegate {
  var playing = false
  var time = 0.0
  var duration = 0.0
  private var p: AVAudioPlayer?
  private var timer: Timer?

  func load(_ url: URL) {
    try? AVAudioSession.sharedInstance().setCategory(.playback)
    p = try? AVAudioPlayer(contentsOf: url)
    p?.delegate = self
    duration = p?.duration ?? 0
  }

  func toggle() {
    guard let p else { return }
    if p.isPlaying { p.pause(); playing = false; timer?.invalidate() } else {
      try? AVAudioSession.sharedInstance().setActive(true)
      p.play(); playing = true
      timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.time = self?.p?.currentTime ?? 0 }
      }
    }
  }

  func seek(_ t: Double) { p?.currentTime = t; time = t }

  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor in self.playing = false; self.timer?.invalidate(); self.time = 0 }
  }
}

struct MeetingDetail: View {
  @Environment(AppModel.self) var m
  @Environment(\.dismiss) var dismiss
  let id: String
  @State private var mode = 0
  @State private var player = Player()
  @State private var renaming: Int?
  @State private var nameDraft = ""
  @State private var titleEdit = false
  @State private var titleDraft = ""

  var meeting: Meeting? { m.meetings.first { $0.id == id } }

  var body: some View {
    Screen(title: meeting?.title ?? "Meeting") {
      if let x = meeting {
        Text(x.id).font(.caption.monospaced()).foregroundStyle(Mono.faint).textSelection(.enabled)
        if x.hasAudio {
          Card {
            HStack(spacing: 14) {
              Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").font(.title3).frame(width: 32) }
              Slider(value: Binding(get: { player.time }, set: { player.seek($0) }), in: 0...max(player.duration, 0.1)).tint(.white)
              Text(durationLabel(player.duration)).font(.caption.monospaced()).foregroundStyle(Mono.dim)
            }
          }
          .task { player.load(m.store.audioURL(id)) }
        }
        Picker("", selection: $mode) {
          Text("Summary").tag(0); Text("Transcript").tag(1); Text("Speakers").tag(2)
        }.pickerStyle(.segmented)
        switch mode {
        case 0: summary(x)
        case 1: transcript(x)
        default: speakers(x)
        }
      } else {
        Text("Meeting not found").foregroundStyle(Mono.dim)
      }
    }
    .toolbar {
      if let x = meeting {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button("Copy transcript", systemImage: "doc.on.doc") { UIPasteboard.general.string = x.fullText }
            Button("Copy ID", systemImage: "number") { UIPasteboard.general.string = x.id }
            ShareLink(item: share(x)) { Label("Share", systemImage: "square.and.arrow.up") }
            Button("Rename", systemImage: "pencil") { titleDraft = x.title; titleEdit = true }
            Button("Delete", systemImage: "trash", role: .destructive) { m.delete(x.id); dismiss() }
          } label: { Image(systemName: "ellipsis.circle") }
        }
      }
    }
    .alert("Rename meeting", isPresented: $titleEdit) {
      TextField("Title", text: $titleDraft)
      Button("Save") { if var x = meeting, !titleDraft.isEmpty { x.title = titleDraft; m.update(x) } }
      Button("Cancel", role: .cancel) {}
    }
    .alert("Rename speaker", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
      TextField("Name", text: $nameDraft)
      Button("Save") {
        if var x = meeting, let s = renaming {
          var names = x.speakerNames ?? [:]
          if nameDraft.isEmpty { names[String(s)] = nil } else { names[String(s)] = nameDraft }
          x.speakerNames = names
          m.update(x)
        }
      }
      Button("Cancel", role: .cancel) {}
    }
    .onDisappear { if player.playing { player.toggle() } }
  }

  func share(_ x: Meeting) -> String {
    "\(x.title)\n\n" + (x.summary.map { "Summary\n\($0)\n\n" } ?? "") + "Transcript\n\(x.fullText)"
  }

  @ViewBuilder func summary(_ x: Meeting) -> some View {
    Card {
      Text("Summary").font(.footnote).foregroundStyle(Mono.faint)
      Text(Digest.sections(x.summary ?? "")["key points"]?.map { "• \($0)" }.joined(separator: "\n") ?? x.summary ?? "No summary yet.").foregroundStyle(.white).textSelection(.enabled)
    }
    ForEach([("Decisions", x.decisions), ("Suggestions", x.suggestions), ("Action items", x.actions)], id: \.0) { title, items in
      if let items, !items.isEmpty {
        Card {
          Text(title).font(.footnote).foregroundStyle(Mono.faint)
          ForEach(items, id: \.self) { Text("• \($0)").foregroundStyle(.white) }
        }
      }
    }
    if let c = x.chapters, !c.isEmpty {
      Card {
        Text("Chapters").font(.footnote).foregroundStyle(Mono.faint)
        ForEach(c, id: \.start) { ch in
          Button { player.seek(ch.start) } label: { Row(title: ch.title, trailing: durationLabel(ch.start)) }
        }
      }
    }
  }

  @ViewBuilder func transcript(_ x: Meeting) -> some View {
    if let turns = x.turns, !turns.isEmpty {
      ForEach(Array(turns.enumerated()), id: \.offset) { _, t in
        Card {
          HStack {
            Text(x.name(t.speaker)).font(.footnote.weight(.medium)).foregroundStyle(Mono.dim)
            Spacer()
            if let s = t.start { Text(durationLabel(s)).font(.caption.monospaced()).foregroundStyle(Mono.faint) }
          }
          Text(t.text).foregroundStyle(.white).textSelection(.enabled)
        }
        .onTapGesture { if let s = t.start { player.seek(s) } }
      }
    } else {
      Card { Text(x.transcript.ifEmpty("No transcript.")).foregroundStyle(.white).textSelection(.enabled) }
    }
  }

  @ViewBuilder func speakers(_ x: Meeting) -> some View {
    Card {
      ForEach(x.speakers.isEmpty ? [0] : x.speakers, id: \.self) { s in
        Button { nameDraft = x.speakerNames?[String(s)] ?? ""; renaming = s } label: {
          Row(title: x.name(s), trailing: "Rename")
        }
      }
    }
  }
}
