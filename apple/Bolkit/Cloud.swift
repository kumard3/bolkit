import BolkitCore
import Foundation

enum Cloud {
  static func trim(_ s: String) -> String {
    var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    while t.hasSuffix("/") { t.removeLast() }
    return t
  }

  static func speechBase(_ s: Settings) -> String {
    let e = s.string("azureSpeechEndpoint")
    if !e.isEmpty { return trim(e) }
    let r = s.string("azureSpeechRegion").trimmingCharacters(in: .whitespaces)
    return r.isEmpty ? "" : "https://\(r).api.cognitive.microsoft.com"
  }

  static func ready(_ id: String, _ s: Settings) -> Bool {
    switch id {
    case "cloud:azure": return !Keychain.get("azureSpeech").isEmpty && !speechBase(s).isEmpty
    case "cloud:azureopenai": return !Keychain.get("azureOpenAI").isEmpty && !s.string("azureOpenAIEndpoint").isEmpty && !s.string("azureOpenAITranscribe").isEmpty
    default: return !Keychain.get("openai").isEmpty && !s.string("cloudBaseUrl", "https://api.openai.com/v1").isEmpty
    }
  }

  static func form(_ parts: [(String, String, Data, String?)]) -> (Data, String) {
    let b = "bolkit-\(UUID().uuidString)"
    var d = Data()
    for (name, file, data, type) in parts {
      d += Data("--\(b)\r\nContent-Disposition: form-data; name=\"\(name)\"\(file.isEmpty ? "" : "; filename=\"\(file)\"")\r\n".utf8)
      if let type { d += Data("Content-Type: \(type)\r\n".utf8) }
      d += Data("\r\n".utf8) + data + Data("\r\n".utf8)
    }
    d += Data("--\(b)--\r\n".utf8)
    return (d, "multipart/form-data; boundary=\(b)")
  }

  static func post(_ url: String, headers: [String: String], parts: [(String, String, Data, String?)]) async throws -> Data {
    guard let u = URL(string: url) else { throw SpeechError("Bad cloud endpoint") }
    let (body, type) = form(parts)
    var req = URLRequest(url: u, timeoutInterval: 300)
    req.httpMethod = "POST"
    req.setValue(type, forHTTPHeaderField: "Content-Type")
    headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
    let (data, res) = try await URLSession.shared.upload(for: req, from: body)
    let code = (res as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(code) else {
      let hint = code == 401 || code == 403 ? " Check the key." : ""
      throw SpeechError("Cloud transcription failed (\(code)).\(hint) \(String(decoding: data.prefix(160), as: UTF8.self))")
    }
    return data
  }

  static func transcribe(_ id: String, file: URL, settings s: Settings, language: String, vocab: [String]) async throws -> [BolkitCore.Word] {
    let wav = try Data(contentsOf: file)
    let seconds = Double(try Audio.samples(file).count) / 16000
    switch id {
    case "cloud:azure":
      var def: [String: Any] = ["enhancedMode": ["enabled": true, "model": "MAI-Transcribe-2", "modelOptions": ["timestamps": "word"]]]
      if !vocab.isEmpty { def["phraseList"] = ["phrases": vocab] }
      let data = try await post("\(speechBase(s))/speechtotext/transcriptions:transcribe?api-version=2025-10-15",
                                headers: ["Ocp-Apim-Subscription-Key": Keychain.get("azureSpeech")],
                                parts: [("audio", "audio.wav", wav, "audio/wav"), ("definition", "", try JSONSerialization.data(withJSONObject: def), nil)])
      return azureWords(data)
    case "cloud:azureopenai":
      let url = "\(trim(s.string("azureOpenAIEndpoint")))/openai/deployments/\(s.string("azureOpenAITranscribe"))/audio/transcriptions?api-version=\(s.string("azureOpenAIApiVersion", "2025-03-01-preview"))"
      return spread(try await post(url, headers: ["api-key": Keychain.get("azureOpenAI")], parts: openAIParts(wav, language, nil)), seconds)
    default:
      let url = "\(trim(s.string("cloudBaseUrl", "https://api.openai.com/v1")))/audio/transcriptions"
      return spread(try await post(url, headers: ["Authorization": "Bearer \(Keychain.get("openai"))"], parts: openAIParts(wav, language, s.string("cloudModel", "whisper-1"))), seconds)
    }
  }

  static func openAIParts(_ wav: Data, _ language: String, _ model: String?) -> [(String, String, Data, String?)] {
    var p: [(String, String, Data, String?)] = [("file", "audio.wav", wav, "audio/wav"), ("response_format", "", Data("json".utf8), nil), ("language", "", Data(language.prefix(2).utf8), nil)]
    if let model { p.append(("model", "", Data(model.utf8), nil)) }
    return p
  }

  static func spread(_ data: Data, _ seconds: Double) -> [BolkitCore.Word] {
    let text = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["text"] as? String) ?? ""
    let ws = text.split(separator: " ")
    guard !ws.isEmpty else { return [] }
    let step = seconds / Double(ws.count)
    return ws.enumerated().map { BolkitCore.Word(text: String($1), start: step * Double($0), end: step * Double($0 + 1)) }
  }

  static func azureWords(_ data: Data) -> [BolkitCore.Word] {
    struct W: Decodable { let text: String; let offsetMilliseconds: Int; let durationMilliseconds: Int? }
    struct P: Decodable { let text: String; let offsetMilliseconds: Int?; let durationMilliseconds: Int?; let words: [W]? }
    struct R: Decodable { let phrases: [P]? }
    var out: [BolkitCore.Word] = []
    for p in (try? JSONDecoder().decode(R.self, from: data))?.phrases ?? [] {
      if let ws = p.words, !ws.isEmpty {
        out += ws.map { BolkitCore.Word(text: $0.text, start: Double($0.offsetMilliseconds) / 1000, end: Double($0.offsetMilliseconds + max($0.durationMilliseconds ?? 0, 1)) / 1000) }
      } else {
        let parts = p.text.replacingOccurrences(of: "\\s*\\n\\s*", with: " ", options: .regularExpression).split(separator: " ")
        let s = Double(p.offsetMilliseconds ?? 0) / 1000, d = Double(p.durationMilliseconds ?? 1000) / 1000
        out += parts.enumerated().map { BolkitCore.Word(text: String($1), start: s + d * Double($0) / Double(parts.count), end: s + d * Double($0 + 1) / Double(parts.count)) }
      }
    }
    return out
  }
}
