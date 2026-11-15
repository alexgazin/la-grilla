import SwiftUI
import MusicDomain
extension Color {
    static let ink = Color(red:0.063,green:0.071,blue:0.086)
    static let panel = Color(red:0.098,green:0.114,blue:0.141)
    static let raised = Color(red:0.137,green:0.165,blue:0.204)
    static let muted = Color(red:0.66,green:0.70,blue:0.76)
    static let mint = Color(red:0.467,green:0.89,blue:0.749)
    static let harmony = Color(red:0.898,green:0.718,blue:0.455)
    static let drums = Color(red:0.518,green:0.616,blue:1)
    static let bass = Color(red:0.729,green:0.612,blue:0.957)
    static let record = Color(red:1,green:0.396,blue:0.467)
    static func track(_ role: TrackRole) -> Color {role == .harmony ? .harmony : role == .drums ? .drums : role == .bass ? .bass : .mint}
}
struct IconButton: View {
    let symbol: String; let label: LocalizedStringKey; var color: Color = .white; let action: () -> Void
    var body: some View {Button(action:action){Image(systemName:symbol).font(.system(size:18,weight:.medium)).foregroundStyle(color).frame(minWidth:44,minHeight:44).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityLabel(label)}
}
struct CapsuleLabel: View {
    let text: String; var color: Color = .muted
    var body: some View {Text(text).font(.system(size:11,weight:.semibold,design:.monospaced)).foregroundStyle(color).padding(.horizontal,9).padding(.vertical,5).background(color.opacity(0.1),in:Capsule())}
}
struct SmallHeading: View {
    let text: LocalizedStringKey
    var body: some View {Text(text).font(.system(size:11,weight:.semibold)).tracking(1.5).foregroundStyle(Color.muted)}
}
