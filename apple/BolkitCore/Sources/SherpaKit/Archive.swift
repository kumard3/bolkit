import CBz
import Foundation

public struct ArchiveError: LocalizedError {
  public let errorDescription: String?
  init(_ m: String) { errorDescription = m }
}

public enum Archive {
  public static func extractTarBz2(_ src: URL, to dst: URL, progress: (Double) -> Void) throws {
    let h = try FileHandle(forReadingFrom: src)
    defer { try? h.close() }
    let total = Double((try? FileManager.default.attributesOfItem(atPath: src.path)[.size] as? Int64) ?? 1)
    var s = bz_stream()
    guard BZ2_bzDecompressInit(&s, 0, 0) == BZ_OK else { throw ArchiveError("Could not start unpacking.") }
    defer { BZ2_bzDecompressEnd(&s) }
    var tar = Untar(root: dst)
    var inb = [CChar](repeating: 0, count: 1 << 20)
    var out = [CChar](repeating: 0, count: 1 << 20)
    var read = 0.0
    var ended = false
    while !ended {
      guard let data = try h.read(upToCount: inb.count), !data.isEmpty else { break }
      read += Double(data.count)
      data.withUnsafeBytes { _ = memcpy(&inb, $0.baseAddress!, data.count) }
      try inb.withUnsafeMutableBufferPointer { ip in
        try out.withUnsafeMutableBufferPointer { op in
          s.next_in = ip.baseAddress
          s.avail_in = UInt32(data.count)
          while s.avail_in > 0 {
            s.next_out = op.baseAddress
            s.avail_out = UInt32(op.count)
            let r = BZ2_bzDecompress(&s)
            guard r == BZ_OK || r == BZ_STREAM_END else { throw ArchiveError("The download is damaged. Try again.") }
            try tar.feed(Data(bytes: op.baseAddress!, count: op.count - Int(s.avail_out)))
            if r == BZ_STREAM_END { ended = true; break }
          }
        }
      }
      progress(read / total)
    }
    guard ended else { throw ArchiveError("The download was incomplete. Try again.") }
  }
}

struct Untar {
  enum Body { case none, file(FileHandle), name, skip }
  let root: URL
  var header = Data()
  var body = Body.none
  var left = 0, padAfter = 0, pad = 0
  var longName = Data()
  var pendingName: String?

  init(root: URL) { self.root = root }

  mutating func feed(_ input: Data) throws {
    var d = input[...]
    while !d.isEmpty {
      if left > 0 {
        let n = min(left, d.count)
        switch body {
        case .file(let f): try f.write(contentsOf: d.prefix(n))
        case .name: longName.append(d.prefix(n))
        default: break
        }
        left -= n
        d = d.dropFirst(n)
        if left == 0 { try endBody() }
      } else if pad > 0 {
        let n = min(pad, d.count)
        pad -= n
        d = d.dropFirst(n)
      } else {
        let n = min(512 - header.count, d.count)
        header.append(d.prefix(n))
        d = d.dropFirst(n)
        if header.count == 512 {
          try begin()
          header = Data()
        }
      }
    }
  }

  mutating func begin() throws {
    if header.allSatisfy({ $0 == 0 }) { return }
    func text(_ r: Range<Int>) -> String { String(decoding: header[r].prefix { $0 != 0 }, as: UTF8.self) }
    let size = Int(text(124..<136).trimmingCharacters(in: .whitespaces), radix: 8) ?? 0
    let prefix = text(345..<500)
    let name = pendingName ?? (prefix.isEmpty ? text(0..<100) : prefix + "/" + text(0..<100))
    pendingName = nil
    left = size
    padAfter = (512 - size % 512) % 512
    switch header[156] {
    case UInt8(ascii: "L"):
      body = .name
      longName = Data()
    case UInt8(ascii: "5"):
      try FileManager.default.createDirectory(at: try path(name), withIntermediateDirectories: true)
      body = .skip
    case UInt8(ascii: "0"), 0:
      let url = try path(name)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      FileManager.default.createFile(atPath: url.path, contents: nil)
      body = .file(try FileHandle(forWritingTo: url))
    default:
      body = .skip
    }
    if left == 0 { try endBody() }
  }

  mutating func endBody() throws {
    switch body {
    case .file(let f): try f.close()
    case .name: pendingName = String(decoding: longName.prefix { $0 != 0 }, as: UTF8.self)
    default: break
    }
    body = .none
    pad = padAfter
  }

  func path(_ name: String) throws -> URL {
    let parts = name.split(separator: "/").map(String.init).filter { $0 != "." }
    guard !parts.contains("..") else { throw ArchiveError("The download is damaged. Try again.") }
    return parts.reduce(root) { $0.appendingPathComponent($1) }
  }
}
