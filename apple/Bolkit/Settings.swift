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
      ForEach(catalog) { x in
        let on = m.models.installed(x)
        HStack(spacing: 10) {
          Button { if on { set(x.id) } else { Task { await m.models.download(x) } } } label: {
            Row(title: x.title, sub: m.models.failure[x.id] ?? x.note, trailing: on ? x.sizeLabel : nil)
          }
          if let p = m.models.progress[x.id] {
            Text("\(Int(p * 100))%").font(.footnote.monospacedDigit()).foregroundStyle(Mono.dim)
          } else if !on {
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
  @State private var lang = "en-US"
  @State private var fields: [String: String] = [:]

  var body: some View {
    Screen(title: "Settings") {
      Card {
        Text("You").font(.footnote).foregroundStyle(Mono.faint)
        TextField("Your name", text: $name).onSubmit { m.yourName = name }.foregroundStyle(.white)
        Picker("Language", selection: $lang) { ForEach(languages, id: \.code) { Text($0.name).tag($0.code) } }
          .onChange(of: lang) { m.language = lang }
        Toggle("Auto polish", isOn: $polish).onChange(of: polish) { m.autoPolish = polish }
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
        Text("About").font(.footnote).foregroundStyle(Mono.faint)
        Row(title: "Bolkit", trailing: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        Text("Voz is powered by Desert Ant Labs.").font(.footnote).foregroundStyle(Mono.dim)
        Text("Everything runs on your phone unless you add a cloud account.").font(.footnote).foregroundStyle(Mono.dim)
      }
    }
    .onAppear {
      name = m.yourName; polish = m.autoPolish; lang = m.language; provider = m.cloudProvider
      vocabText = m.vocab.joined(separator: ", ")
      for k in ["azureSpeechRegion", "azureOpenAIEndpoint", "azureOpenAITranscribe", "azureOpenAIChat", "cloudBaseUrl", "cloudModel"] { fields[k] = m.text(k) }
      for k in ["openai", "azureSpeech", "azureOpenAI"] { keys[k] = Keychain.get(k) }
    }
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
  @State private var step = 0
  @State private var granted = false

  var body: some View {
    VStack(spacing: 26) {
      Spacer()
      Image(systemName: step == 0 ? "waveform" : step == 1 ? "mic" : "cpu").font(.system(size: 56, weight: .thin)).foregroundStyle(.white)
      Text(["Welcome to Bolkit", "Allow the microphone", "Choose a model"][step]).font(.title.weight(.semibold)).foregroundStyle(.white)
      Text(["Speak, and it writes. Private, on your phone.", "Bolkit needs the mic and speech recognition to hear you.", "Pick how Bolkit transcribes. You can change it later."][step])
        .multilineTextAlignment(.center).foregroundStyle(Mono.dim).padding(.horizontal, 32)
      if step == 2 {
        VStack {
          ForEach(catalog) { x in
            Button { if x.kind == .apple { m.dictationModel = x.id } } label: {
              HStack {
                Row(title: x.title, sub: x.note)
                if m.dictationModel == x.id && x.kind == .apple { Image(systemName: "checkmark.circle.fill") }
              }.padding(12).background(Mono.surface, in: RoundedRectangle(cornerRadius: 14))
            }.opacity(x.kind == .apple ? 1 : 0.45)
          }
        }.padding(.horizontal, 20)
      }
      Spacer()
      Button {
        Task {
          if step == 1 { granted = await Speech.authorize() }
          if step == 2 { m.onboarded = true; done() } else { step += 1 }
        }
      } label: {
        Text(step == 2 ? "Start" : step == 1 ? "Allow" : "Continue").font(.headline).foregroundStyle(.black)
          .frame(maxWidth: .infinity).padding(.vertical, 16).background(.white, in: Capsule())
      }.padding(.horizontal, 28)
      if step == 1 { Button("Not now") { step += 1 }.font(.footnote).foregroundStyle(Mono.dim) }
    }
    .padding(.bottom, 20)
    .background(Mono.bg.ignoresSafeArea())
  }
}
