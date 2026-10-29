import WidgetKit
import SwiftUI

struct BolkitEntry: TimelineEntry {
  let date: Date
}

struct BolkitProvider: TimelineProvider {
  func placeholder(in context: Context) -> BolkitEntry { BolkitEntry(date: Date()) }
  func getSnapshot(in context: Context, completion: @escaping (BolkitEntry) -> Void) {
    completion(BolkitEntry(date: Date()))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<BolkitEntry>) -> Void) {
    completion(Timeline(entries: [BolkitEntry(date: Date())], policy: .never))
  }
}


struct WidgetBackground: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 17.0, *) {
      content.containerBackground(Color.black, for: .widget)
    } else {
      content.background(Color.black)
    }
  }
}

struct BolkitWidgetEntryView: View {
  var entry: BolkitProvider.Entry
  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: "mic.fill").font(.system(size: 30)).foregroundColor(.white)
      Text("Bolkit · Dictate")
        .font(.system(size: 13, weight: .bold))
        .foregroundColor(.white)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .widgetURL(URL(string: "scribe://dictate-session"))
    .modifier(WidgetBackground())
  }
}

@main
struct BolkitWidget: Widget {
  let kind = "ScribeWidget"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: BolkitProvider()) { entry in
      BolkitWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("Bolkit Dictate")
    .description("Tap to start on-device dictation.")
    .supportedFamilies([.systemSmall])
  }
}
