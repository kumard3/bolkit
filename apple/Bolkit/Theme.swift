import SwiftUI

enum Mono {
  static let bg = Color(hex: 0x000000)
  static let surface = Color(hex: 0x141416)
  static let surfaceAlt = Color(hex: 0x1C1C1F)
  static let border = Color(hex: 0x2A2A2E)
  static let dim = Color(hex: 0x9A9AA3)
  static let faint = Color(hex: 0x5C5C66)
}

extension Color {
  init(hex: UInt32) {
    self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
  }
}

struct Card<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 12) { content }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
      .background(Mono.surface, in: RoundedRectangle(cornerRadius: 18))
      .overlay(RoundedRectangle(cornerRadius: 18).stroke(Mono.border, lineWidth: 0.5))
  }
}

struct Screen<Content: View>: View {
  let title: String
  @ViewBuilder var content: Content
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) { content }.padding(.horizontal, 16).padding(.bottom, 32)
    }
    .background(Mono.bg.ignoresSafeArea())
    .navigationTitle(title)
    .toolbarColorScheme(.dark, for: .navigationBar)
  }
}

struct RoundMic: View {
  var icon: String
  var active: Bool
  var size: CGFloat = 112
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      Image(systemName: icon).font(.system(size: size * 0.34, weight: .medium))
        .foregroundStyle(active ? .black : .white)
        .frame(width: size, height: size)
        .background(active ? AnyShapeStyle(.white) : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x2A2A2E), Color(hex: 0x111113)], startPoint: .top, endPoint: .bottom)), in: Circle())
        .overlay(Circle().stroke(.white.opacity(active ? 0 : 0.18), lineWidth: 1))
        .shadow(color: .white.opacity(active ? 0.35 : 0.06), radius: active ? 24 : 12)
    }
    .buttonStyle(.plain)
  }
}

struct Waveform: View {
  var levels: [Float]
  var body: some View {
    Canvas { ctx, size in
      let n = 48, w = size.width / CGFloat(n)
      for i in 0..<n {
        let idx = levels.count - n + i
        let v = idx >= 0 ? CGFloat(min(1, levels[idx])) : 0
        let h = max(3, v * size.height)
        ctx.fill(Path(roundedRect: CGRect(x: CGFloat(i) * w + 1, y: (size.height - h) / 2, width: w - 3, height: h), cornerRadius: 2), with: .color(.white.opacity(0.35 + 0.65 * Double(v))))
      }
    }
    .frame(height: 64)
  }
}

struct Row: View {
  var title: String
  var sub: String? = nil
  var trailing: String? = nil
  var badge: String? = nil
  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 8) {
          Text(title).foregroundStyle(.white)
          if let badge { Text(badge).font(.caption2.weight(.semibold)).foregroundStyle(.black).padding(.horizontal, 7).padding(.vertical, 2).background(.white, in: Capsule()) }
        }
        if let sub { Text(sub).font(.footnote).foregroundStyle(Mono.dim) }
      }
      Spacer()
      if let trailing { Text(trailing).font(.footnote).foregroundStyle(Mono.dim) }
    }
  }
}
