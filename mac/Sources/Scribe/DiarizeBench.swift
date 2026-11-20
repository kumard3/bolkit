import Foundation
import FluidAudio
import Who

enum DiarizeBench {
  static func runIfRequested() {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--diarize-bench"), args.count > i + 3 else { return }
    let list = args[i + 1], engine = args[i + 2], outDir = args[i + 3]
    var opt: [String: Double] = [:]
    for a in args[(i + 4)...] {
      let kv = a.split(separator: "=", maxSplits: 1).map(String.init)
      if kv.count == 2, let v = Double(kv[1]) { opt[kv[0]] = v }
    }
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    let files = ((try? String(contentsOfFile: list, encoding: .utf8)) ?? "")
      .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    Task.detached {
      var fluid: OfflineDiarizerManager?
      var sortformer: OfflineSortformerDiarizer?
      let who = Who()
      if engine == "fluid" {
        var cfg = OfflineDiarizerConfig.default
        if let v = opt["threshold"] { cfg.clustering.threshold = v }
        if let v = opt["speakers"], v > 0 { cfg.clustering.numSpeakers = Int(v) }
        if let v = opt["maxSpeakers"] { cfg.clustering.maxSpeakers = Int(v) }
        if let v = opt["minSegment"] { cfg.embedding.minSegmentDurationSeconds = v }
        if let v = opt["minGap"] { cfg.postProcessing.minGapDurationSeconds = v }
        let m = OfflineDiarizerManager(config: cfg)
        try await m.prepareModels()
        fluid = m
      }
      for path in files {
        let parts = path.split(separator: "\t").map(String.init)
        guard parts.count == 3 else { continue }
        let name = parts[0]
        let outPath = "\(outDir)/\(name).json"
        if FileManager.default.fileExists(atPath: outPath) { continue }
        guard let you = AudioImport.decode(URL(fileURLWithPath: parts[1])),
              let others = AudioImport.decode(URL(fileURLWithPath: parts[2])) else { continue }
        let y = SileroVAD.resampleTo16k(you.samples, from: you.sampleRate)
        let o = SileroVAD.resampleTo16k(others.samples, from: others.sampleRate)
        let n = min(y.count, o.count)
        let samples: [Float] = opt["track"] == 1 ? Array(o[0..<n]) : (0..<n).map { max(-1, min(1, y[$0] + o[$0])) }
        let seconds = Double(samples.count) / 16000
        let start = Date()
        var segs: [(Double, Double, Int)] = []
        do {
          switch engine {
          case "who":
            let r = try await who.diarize(samples: samples, sampleRate: 16000)
            segs = r.turns.map { ($0.start, $0.end, $0.speaker) }
          case "sortformer":
            var tl = DiarizerTimelineConfig.sortformerDefault
            if let v = opt["onset"] { tl.onsetThreshold = Float(v) }
            if let v = opt["offset"] { tl.offsetThreshold = Float(v) }
            if let v = opt["pad"] { tl.onsetPadSeconds = Float(v); tl.offsetPadSeconds = Float(v) }
            if let v = opt["minOn"] { tl.minDurationOn = Float(v) }
            if let v = opt["minOff"] { tl.minDurationOff = Float(v) }
            if sortformer == nil {
              let d = OfflineSortformerDiarizer(config: .offlineV2_1, timelineConfig: tl)
              try await d.initializeFromHuggingFace()
              sortformer = d
            }
            let t = try sortformer!.processComplete(samples)
            segs = t.speakers.values.flatMap(\.finalizedSegments)
              .map { (Double($0.startTime), Double($0.endTime), $0.speakerIndex) }
          case "pyannote":
            segs = Diarizer.diarize(
              samples: samples, sampleRate: 16000, numSpeakers: Int(opt["speakers"] ?? 0),
              threshold: Float(opt["threshold"] ?? 0.8), minOn: Float(opt["minOn"] ?? 0.3), minOff: Float(opt["minOff"] ?? 0.5)
            ).map { ($0.start, $0.end, $0.speaker) }
          case "fluid":
            let r = try await fluid!.process(audio: samples)
            var ids: [String: Int] = [:]
            segs = r.segments.map { s in
              if ids[s.speakerId] == nil { ids[s.speakerId] = ids.count }
              return (Double(s.startTimeSeconds), Double(s.endTimeSeconds), ids[s.speakerId]!)
            }
          default:
            break
          }
        } catch {
          FileHandle.standardError.write("\(name): \(error)\n".data(using: .utf8)!)
          continue
        }
        let wall = Date().timeIntervalSince(start)
        let body: [String: Any] = ["seconds": seconds, "wall": wall, "segs": segs.map { [$0.0, $0.1, Double($0.2)] }]
        if let data = try? JSONSerialization.data(withJSONObject: body) { try? data.write(to: URL(fileURLWithPath: outPath)) }
        print("\(name) \(String(format: "%.0f", seconds)) s wall \(String(format: "%.1f", wall)) s speakers \(Set(segs.map { $0.2 }).count)")
        fflush(stdout)
      }
      exit(0)
    }
    dispatchMain()
  }
}
