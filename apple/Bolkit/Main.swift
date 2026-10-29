import BolkitCore
import SwiftUI

@main
struct BolkitApp: App {
  @State private var model = AppModel()
  var body: some Scene {
    WindowGroup {
      Root().environment(model).preferredColorScheme(.dark).tint(.white)
        .task { await model.runSelfTest() }
    }
  }
}

struct Root: View {
  @Environment(AppModel.self) var m
  @State private var onboarding = false

  var body: some View {
    @Bindable var m = m
    TabView(selection: $m.tab) {
      NavigationStack { HomeView() }.tabItem { Label("Dictate", systemImage: "mic") }.tag(0)
      NavigationStack { RecordView() }.tabItem { Label("Record", systemImage: "record.circle") }.tag(1)
      NavigationStack { MeetingsView() }.tabItem { Label("Meetings", systemImage: "list.bullet") }.tag(2)
      NavigationStack { ModelsView() }.tabItem { Label("Models", systemImage: "cpu") }.tag(3)
      NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "gearshape") }.tag(4)
    }
    .toolbarBackground(Mono.bg, for: .tabBar)
    .toolbarBackground(.visible, for: .tabBar)
    .onOpenURL { url in
      guard url.host == "dictate-session" else { return }
      m.tab = 0
      m.copyOnFinish = true
      if !m.dictating { Task { await m.toggleDictate() } }
    }
    .fullScreenCover(isPresented: $onboarding) { Onboarding { onboarding = false } }
    .onAppear {
      onboarding = !m.onboarded || UserDefaults.standard.bool(forKey: "forceOnboarding")
      if UserDefaults.standard.object(forKey: "tab") != nil { m.tab = UserDefaults.standard.integer(forKey: "tab") }
      if UserDefaults.standard.bool(forKey: "openFirst") { m.openID = m.meetings.first?.id }
    }
    .alert("Something went wrong", isPresented: Binding(get: { m.error != nil }, set: { if !$0 { m.error = nil } })) {
      Button("OK") {}
    } message: { Text(m.error ?? "") }
  }
}

struct HomeView: View {
  @Environment(AppModel.self) var m

  var body: some View {
    Screen(title: "Bolkit") {
      VStack(spacing: 18) {
        RoundMic(icon: m.dictating ? "stop.fill" : "mic.fill", active: m.dictating) { Task { await m.toggleDictate() } }
          .padding(.top, 24)
        if m.dictating { Waveform(levels: m.capture.levels) }
        Text(m.dictating ? (m.copyOnFinish ? "Listening. Tap stop, then swipe back and Paste" : "Listening") : "Tap to dictate").font(.footnote).foregroundStyle(Mono.dim)
      }
      .frame(maxWidth: .infinity)

      if !m.dictText.isEmpty {
        Card {
          Text(m.dictText).foregroundStyle(.white).textSelection(.enabled)
          HStack(spacing: 20) {
            Button { UIPasteboard.general.string = m.dictText } label: { Label("Copy", systemImage: "doc.on.doc") }
            ShareLink(item: m.dictText) { Label("Share", systemImage: "square.and.arrow.up") }
          }.font(.footnote).foregroundStyle(Mono.dim)
        }
      }

      if !m.history.isEmpty {
        Text("Recent").font(.footnote).foregroundStyle(Mono.faint).padding(.top, 8)
        ForEach(m.history.prefix(12)) { h in
          Card {
            Text(h.text).foregroundStyle(.white).lineLimit(4)
            Text(h.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Mono.faint)
          }
          .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = h.text }
            Button("Delete", systemImage: "trash", role: .destructive) { m.deleteHistory(h.id) }
          }
        }
      }
    }
  }
}

struct RecordView: View {
  @Environment(AppModel.self) var m

  var body: some View {
    let c = m.capture
    Screen(title: "Record") {
      VStack(spacing: 22) {
        Text(durationLabel(c.seconds)).font(.system(size: 56, weight: .thin, design: .monospaced)).foregroundStyle(.white).padding(.top, 32)
        Waveform(levels: c.levels)
        if c.state == .interrupted {
          Text("Interrupted. Your audio so far is safe.").font(.footnote).foregroundStyle(Mono.dim)
        }
        if m.busy {
          ProgressView("Transcribing").tint(.white).foregroundStyle(Mono.dim)
        } else if m.recordingID == nil {
          RoundMic(icon: "record.circle", active: false) { Task { await m.startRecording() } }
          Text("Tap to record a meeting").font(.footnote).foregroundStyle(Mono.dim)
        } else {
          HStack(spacing: 28) {
            RoundMic(icon: c.state == .recording ? "pause.fill" : "play.fill", active: false, size: 80) {
              c.state == .recording ? c.pause() : c.resume()
            }
            RoundMic(icon: "stop.fill", active: true, size: 96) { Task { await m.stopRecording() } }
          }
        }
      }
      .frame(maxWidth: .infinity)
    }
  }
}
