import BolkitCore
import SwiftUI

struct ModelsView: View {
  @Environment(AppModel.self) var m
  @State private var installing = false
  @State private var note: String?

  var body: some View {
    Screen(title: "Models") {
      picker("Dictation", selected: m.dictationModel) { m.dictationModel = $0 }
      picker("Meetings", selected: m.meetingModel) { m.meetingModel = $0 }
      Card {
        let sf = modelInfo("sortformer")
        Text("Speakers (meetings)").font(.footnote).foregroundStyle(Mono.faint)
        HStack {
          Row(title: sf.title, sub: m.models.failure[sf.id] ?? sf.note, trailing: m.models.installed(sf) ? sf.sizeLabel : nil)
          if let p = m.models.progress[sf.id] {
            Text("\(Int(p * 100))%").font(.footnote.monospacedDigit()).foregroundStyle(Mono.dim)
          } else if m.models.installed(sf) {
            Button { m.models.delete(sf) } label: { Image(systemName: "trash") }.foregroundStyle(Mono.faint)
          } else {
            Button { Task { await m.models.download(sf) } } label: { Image(systemName: "arrow.down.circle") }.foregroundStyle(.white)
          }
        }
      }
      Card {
        Text("Apple Speech language").font(.footnote).foregroundStyle(Mono.faint)
        Row(title: languages.first { $0.code == m.language }?.name ?? m.language, sub: note)
        Button { Task { await install() } } label: {
          if installing { ProgressView().tint(.white) } else { Label("Download language", systemImage: "arrow.down.circle") }
        }.disabled(installing).foregroundStyle(.white)
      }
    }
  }

  func picker(_ title: String, selected: String, set: @escaping (String) -> Void) -> some View {
    Card {
      Text(title).font(.footnote).foregroundStyle(Mono.faint)
      ForEach(catalog.filter { $0.kind != .speakers }) { x in
        let on = m.models.installed(x)
        HStack(spacing: 10) {
          Button { if on { set(x.id) } else if x.kind == .cloud { m.tab = 4 } else { Task { await m.models.download(x) } } } label: {
            Row(title: x.title, sub: m.models.failure[x.id] ?? x.note, trailing: on ? x.sizeLabel : x.kind == .cloud ? "Add key" : nil, badge: x.id == "system" ? "Suggested" : nil)
          }
          if let p = m.models.progress[x.id] {
            Text("\(Int(p * 100))%").font(.footnote.monospacedDigit()).foregroundStyle(Mono.dim)
          } else if !on && x.kind != .cloud {
            Button { Task { await m.models.download(x) } } label: { Image(systemName: "arrow.down.circle") }.foregroundStyle(.white)
          } else {
            if x.kind == .whisper || x.kind == .voz || x.kind == .parakeet {
              Button { m.models.delete(x); if selected == x.id { set("system") } } label: { Image(systemName: "trash") }.foregroundStyle(Mono.faint)
            }
            Image(systemName: selected == x.id ? "checkmark.circle.fill" : "circle").foregroundStyle(selected == x.id ? .white : Mono.faint)
          }
        }
        if x.id != catalog.last?.id { Divider().overlay(Mono.border) }
      }
    }
  }

  func install() async {
    installing = true
    note = nil
    do { try await Speech.prepare(locale: m.language); note = "Ready" } catch { note = error.localizedDescription }
    installing = false
  }
}

struct SettingsView: View {
  @Environment(AppModel.self) var m
  @State private var vocabText = ""
  @State private var keys: [String: String] = [:]
  @State private var provider = "openai"
  @State private var name = ""
  @State private var polish = false
  @State private var smart = true
  @State private var wipe = false
  @State private var lang = "en-US"
  @State private var target = ""
  @State private var fields: [String: String] = [:]

  var body: some View {
    Screen(title: "Settings") {
      Card {
        Text("You").font(.footnote).foregroundStyle(Mono.faint)
        TextField("Your name", text: $name).onSubmit { m.yourName = name }.foregroundStyle(.white)
        LabeledContent("Language") {
          Picker("Language", selection: $lang) { ForEach(languages, id: \.code) { Text($0.name).tag($0.code) } }.labelsHidden()
        }.onChange(of: lang) { m.language = lang }
        LabeledContent("Translate to") {
          Picker("Translate to", selection: $target) {
            Text("Off").tag("")
            ForEach(targets, id: \.code) { Text($0.name).tag($0.code) }
          }.labelsHidden()
        }.onChange(of: target) { m.translateTarget = target }
        Toggle("Auto polish", isOn: $polish).onChange(of: polish) { m.autoPolish = polish }
        Toggle(isOn: $smart) {
          Text("Smart corrections")
          Text(Brain.available ? "Understands \"no wait\" and \"actually\"." : "Needs Apple Intelligence.")
        }.onChange(of: smart) { m.smartCorrections = smart }
      }
      Card {
        Text("Keyboard").font(.footnote).foregroundStyle(Mono.faint)
        LabeledContent("Session length") {
          Picker("Session length", selection: Binding(get: { m.text("flowMinutes").ifEmpty("15") }, set: { m.setText("flowMinutes", $0) })) {
            Text("5 minutes").tag("5")
            Text("15 minutes").tag("15")
            Text("1 hour").tag("60")
            Text("Until I stop").tag("0")
          }.labelsHidden()
        }
        LabeledContent("Return to") {
          Picker("Return to", selection: Binding(get: { m.text("flowReturn") }, set: { m.setText("flowReturn", $0) })) {
            Text("Swipe back").tag("")
            ForEach(Flow.apps, id: \.name) { Text($0.name).tag($0.name) }
          }.labelsHidden()
        }
      }
      Card {
        Text("Vocabulary").font(.footnote).foregroundStyle(Mono.faint)
        TextField("Names and jargon, comma separated", text: $vocabText, axis: .vertical)
          .onSubmit { m.vocab = vocabText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
          .foregroundStyle(.white)
      }
      Card {
        Text("Cloud accounts").font(.footnote).foregroundStyle(Mono.faint)
        Picker("Provider", selection: $provider) {
          Text("OpenAI compatible").tag("openai"); Text("Azure Speech").tag("azureSpeech"); Text("Azure OpenAI").tag("azureOpenAI")
        }.onChange(of: provider) { m.cloudProvider = provider }
        switch provider {
        case "azureSpeech":
          field("Region", "azureSpeechRegion"); secret("Speech key", "azureSpeech")
        case "azureOpenAI":
          field("Endpoint", "azureOpenAIEndpoint"); field("Transcribe deployment", "azureOpenAITranscribe"); field("Chat deployment", "azureOpenAIChat"); secret("API key", "azureOpenAI")
        default:
          field("Base URL", "cloudBaseUrl"); field("Model", "cloudModel"); secret("API key", "openai")
        }
        Text("Keys are kept in the iOS Keychain.").font(.caption).foregroundStyle(Mono.faint)
      }
      Card {
        Text("Stats").font(.footnote).foregroundStyle(Mono.faint)
        Row(title: "Meetings", trailing: "\(m.meetings.count)")
        Row(title: "Recorded", trailing: durationLabel(m.meetings.reduce(0) { $0 + $1.durationSec }))
        Row(title: "Dictations", trailing: "\(m.history.count)")
        Row(title: "Words dictated", trailing: "\(m.history.reduce(0) { $0 + $1.text.split(separator: " ").count })")
      }
      Card {
        Button("Delete all data", role: .destructive) { wipe = true }.disabled(!m.canDeleteAll)
        Text("Removes every dictation, meeting, model and key from this iPhone.").font(.caption).foregroundStyle(Mono.faint)
      }
      Card {
        Text("About").font(.footnote).foregroundStyle(Mono.faint)
        Row(title: "Bolkit", trailing: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        Text("Voz is powered by Desert Ant Labs.").font(.footnote).foregroundStyle(Mono.dim)
        Text("Everything runs on your phone unless you add a cloud account.").font(.footnote).foregroundStyle(Mono.dim)
      }
    }
    .confirmationDialog("Delete all data?", isPresented: $wipe, titleVisibility: .visible) {
      Button("Delete everything", role: .destructive) { m.deleteAll(); load() }
    } message: { Text("This cannot be undone.") }
    .onAppear(perform: load)
  }

  func load() {
      name = m.yourName; polish = m.autoPolish; smart = m.smartCorrections; target = m.translateTarget; lang = m.language; provider = m.cloudProvider
      vocabText = m.vocab.joined(separator: ", ")
      for k in ["azureSpeechRegion", "azureOpenAIEndpoint", "azureOpenAITranscribe", "azureOpenAIChat", "cloudBaseUrl", "cloudModel"] { fields[k] = m.text(k) }
      for k in ["openai", "azureSpeech", "azureOpenAI"] { keys[k] = Keychain.get(k) }
  }

  func field(_ title: String, _ key: String) -> some View {
    TextField(title, text: Binding(get: { fields[key] ?? "" }, set: { fields[key] = $0; m.setText(key, $0) }))
      .textInputAutocapitalization(.never).autocorrectionDisabled().foregroundStyle(.white)
  }

  func secret(_ title: String, _ account: String) -> some View {
    SecureField(title, text: Binding(get: { keys[account] ?? "" }, set: { keys[account] = $0; Keychain.set(account, $0) }))
      .foregroundStyle(.white)
  }
}

struct Onboarding: View {
  @Environment(AppModel.self) var m
  var done: () -> Void
  @State private var step = UserDefaults.standard.integer(forKey: "onboardingStep")
  @State private var pick = Onboarding.suggested
  @State private var lang = "es-ES"

  static let india = Locale.current.region?.identifier == "IN"
  static let suggested = india ? 1 : 0

  var body: some View {
    VStack(spacing: 22) {
      Spacer()
      Image(systemName: step == 0 ? "waveform" : "character.bubble").font(.system(size: 56, weight: .thin)).foregroundStyle(.white)
      Text(step == 0 ? "Welcome to Bolkit" : "How do you speak?").font(.title.weight(.semibold)).foregroundStyle(.white)
      Text(step == 0 ? "Speak, and it writes. Private, on your phone." : "You can change this any time in Settings.")
        .multilineTextAlignment(.center).foregroundStyle(Mono.dim).padding(.horizontal, 32)
      if step == 1 {
        VStack(spacing: 10) {
          choice(0, "English", "Built in. Nothing to download.")
          choice(1, "Hinglish", "Hindi and English mixed, written in English letters. Built in, live as you speak.")
          choice(2, "Another language", "Built in. Pick your language.")
          if pick == 2 {
            Picker("Language", selection: $lang) { ForEach(languages.filter { !$0.code.hasPrefix("en") && $0.code != "hi-IN" }, id: \.code) { Text($0.name).tag($0.code) } }
          }
        }.padding(.horizontal, 20)
      }
      Spacer()
      Button {
        Task {
          if step == 0 { _ = await Speech.authorize(); step = 1 } else { apply(); m.onboarded = true; done() }
        }
      } label: {
        Text(step == 0 ? "Continue" : "Start").font(.headline).foregroundStyle(.black)
          .frame(maxWidth: .infinity).padding(.vertical, 16).background(.white, in: Capsule())
      }.padding(.horizontal, 28)
    }
    .padding(.bottom, 20)
    .background(Mono.bg.ignoresSafeArea())
  }

  func choice(_ i: Int, _ title: String, _ sub: String) -> some View {
    Button { pick = i } label: {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 8) {
            Text(title).foregroundStyle(.white)
            if i == Onboarding.suggested {
              Text("Suggested").font(.caption2.weight(.semibold)).foregroundStyle(.black).padding(.horizontal, 7).padding(.vertical, 2).background(.white, in: Capsule())
            }
          }
          Text(sub).font(.footnote).foregroundStyle(Mono.dim).multilineTextAlignment(.leading)
        }
        Spacer()
        Image(systemName: pick == i ? "checkmark.circle.fill" : "circle").foregroundStyle(pick == i ? .white : Mono.faint)
      }
      .padding(14)
      .background(Mono.surface, in: RoundedRectangle(cornerRadius: 14))
      .overlay(RoundedRectangle(cornerRadius: 14).stroke(pick == i ? .white.opacity(0.6) : Mono.border, lineWidth: 1))
    }.buttonStyle(.plain)
  }

  func apply() {
    switch pick {
    case 1:
      m.language = "hi-IN"; m.dictationModel = "system"; m.meetingModel = "system"
    case 2:
      m.language = lang; m.dictationModel = "system"; m.meetingModel = "system"
    default:
      m.language = Onboarding.india ? "en-IN" : "en-US"; m.dictationModel = "system"; m.meetingModel = "system"
    }
  }
}
