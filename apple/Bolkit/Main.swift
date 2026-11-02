import BolkitCore
import UniformTypeIdentifiers
import SwiftUI
import Translation

@main
struct BolkitApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
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
    .onChange(of: Shortcut.shared.type, initial: true) { _, t in
      guard let t else { return }
      Shortcut.shared.type = nil
      m.tab = 0
      if t == "history" { m.showHistory = true } else if !m.dictating { Task { await m.toggleDictate() } }
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
  @State private var working = false
  @State private var tr: TranslationSession.Configuration?

  var body: some View {
    @Bindable var m = m
    Screen(title: "Bolkit") {
      VStack(spacing: 18) {
        RoundMic(icon: m.dictating ? "stop.fill" : "mic.fill", active: m.dictating) { Task { await m.toggleDictate() } }
          .padding(.top, 24)
        if m.dictating { Waveform(levels: m.capture.levels) }
        Text(m.dictating ? (m.copyOnFinish ? "Listening. Tap stop, then swipe back and Paste" : "Listening") : m.busy ? "Transcribing" : "Tap to dictate").font(.footnote).foregroundStyle(Mono.dim)
      }
      .frame(maxWidth: .infinity)

      if !m.dictText.isEmpty {
        Card {
          if m.dictating {
            Text(m.dictText).foregroundStyle(.white)
          } else {
            TextEditor(text: Binding(get: { m.dictText }, set: { m.setDictText($0) }))
              .scrollContentBackground(.hidden).foregroundStyle(.white).frame(minHeight: 120)
          }
          HStack(spacing: 18) {
            Button { UIPasteboard.general.string = m.dictText } label: { Label("Copy", systemImage: "doc.on.doc") }
            ShareLink(item: m.dictText) { Label("Share", systemImage: "square.and.arrow.up") }
            Spacer()
            if working { ProgressView().tint(.white) } else {
              Menu {
                Button("Polish", systemImage: "wand.and.stars") { run { await m.polishDictation() } }
                Button("Translate to \(targets.first { $0.code == m.translateTarget.ifEmpty("en") }?.name ?? "English")", systemImage: "translate") { translate() }
                if m.dictText.count > 160 { Button("Summarize", systemImage: "text.redaction") { run { await m.summarizeDictation() } } }
                Button("Clear", systemImage: "xmark") { m.dictText = ""; m.dictID = nil }
              } label: { Image(systemName: "ellipsis.circle") }
            }
          }.font(.footnote).foregroundStyle(Mono.dim).disabled(m.dictating)
        }
      }

      if !m.history.isEmpty {
        HStack {
          Text("Recent").font(.footnote).foregroundStyle(Mono.faint)
          Spacer()
          Button("See all") { m.showHistory = true }.font(.footnote).foregroundStyle(Mono.dim)
        }.padding(.top, 8)
        ForEach(m.history.prefix(5)) { h in HistoryRow(h: h) }
      }
    }
    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { m.showHistory = true } label: { Image(systemName: "clock") } } }
    .navigationDestination(isPresented: $m.showHistory) { HistoryView() }
    .onChange(of: m.translateTick) { translate() }
    .translationTask(tr) { session in await translated(session) }
  }

  func translate() {
    let target = Locale.Language(identifier: m.translateTarget.ifEmpty("en"))
    if tr?.target == target { tr?.invalidate() } else { tr = .init(source: nil, target: target) }
  }

  func translated(_ session: TranslationSession) async {
    let code = m.translateTarget.ifEmpty("en")
    working = true
    defer { working = false }
    do { m.saveTranslation(try await session.translate(m.dictText).targetText, to: code) } catch {
      m.error = "Could not translate. \(error.localizedDescription)"
    }
  }

  func run(_ f: @escaping () async -> Void) {
    working = true
    Task { await f(); working = false }
  }
}

struct HistoryRow: View {
  @Environment(AppModel.self) var m
  @Environment(\.dismiss) var dismiss
  let h: HistoryItem
  var pops = false

  var body: some View {
    Button { m.open(h); if pops { dismiss() } } label: {
      Card {
        Text(h.text).foregroundStyle(.white).lineLimit(4).multilineTextAlignment(.leading)
        Text(h.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Mono.faint)
      }
    }
    .buttonStyle(.plain)
    .contextMenu {
      Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = h.text }
      ShareLink(item: h.text) { Label("Share", systemImage: "square.and.arrow.up") }
      Button("Delete", systemImage: "trash", role: .destructive) { m.deleteHistory(h.id) }
    }
  }
}

struct HistoryView: View {
  @Environment(AppModel.self) var m
  @State private var query = ""
  @State private var confirm = false

  var shown: [HistoryItem] { query.isEmpty ? m.history : m.history.filter { $0.text.localizedCaseInsensitiveContains(query) } }

  var body: some View {
    Screen(title: "History") {
      if shown.isEmpty { Text(m.history.isEmpty ? "No dictations yet." : "No matches.").foregroundStyle(Mono.dim) }
      ForEach(shown) { h in HistoryRow(h: h, pops: true) }
    }
    .searchable(text: $query, prompt: "Search dictations")
    .toolbar { if !m.history.isEmpty { Button("Clear all", role: .destructive) { confirm = true } } }
    .confirmationDialog("Delete all dictations?", isPresented: $confirm, titleVisibility: .visible) {
      Button("Delete all", role: .destructive) { m.clearHistory() }
    }
  }
}

struct RecordView: View {
  @Environment(AppModel.self) var m
  @State private var importing = false

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
          Button { importing = true } label: { Label("Import an audio file", systemImage: "square.and.arrow.down") }
            .font(.footnote).foregroundStyle(.white).padding(.top, 12)
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
    .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { r in
      if case .success(let url) = r { Task { await m.importAudio(url) } }
    }
  }
}

@MainActor @Observable
final class Shortcut {
  static let shared = Shortcut()
  var type: String?
}

final class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    if let item = options.shortcutItem { MainActor.assumeIsolated { Shortcut.shared.type = item.type } }
    let c = UISceneConfiguration(name: nil, sessionRole: session.role)
    if session.role == .windowApplication { c.delegateClass = SceneDelegate.self }
    return c
  }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
  func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
    MainActor.assumeIsolated { Shortcut.shared.type = shortcutItem.type }
    completionHandler(true)
  }
}
