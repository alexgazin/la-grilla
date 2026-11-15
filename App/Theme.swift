import SwiftUI
import MusicDomain
import UIKit
extension Color {
    private static func adaptive(_ dark:UInt32,_ light:UInt32)->Color {
        Color(uiColor:UIColor{trait in let hex=trait.userInterfaceStyle == .dark ? dark:light;return UIColor(red:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1)})
    }
    static let ink=adaptive(0x101216,0xF2F4F7)
    static let panel=adaptive(0x191D24,0xFFFFFF)
    static let raised=adaptive(0x232A34,0xE6EBF0)
    static let muted=adaptive(0xA8B3C2,0x536072)
    static let mint=adaptive(0x77E3BF,0x00674C)
    static let harmony=adaptive(0xE5B774,0x7D4D09)
    static let drums=adaptive(0x849DFF,0x3454BE)
    static let bass=adaptive(0xBA9CF4,0x7048A7)
    static let record=adaptive(0xFF6577,0xB71D43)
    static func track(_ role: TrackRole) -> Color {role == .harmony ? .harmony : role == .drums ? .drums : role == .bass ? .bass : .mint}
}
struct IconButton: View {
    let symbol: String; let label: LocalizedStringKey; var color: Color = .primary; let action: () -> Void
    var body: some View {Button(action:action){Image(systemName:symbol).font(.system(size:18,weight:.medium)).foregroundStyle(color).frame(minWidth:44,minHeight:44).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityLabel(label)}
}
struct CapsuleLabel: View {
    let text: String; var color: Color = .muted
    var body: some View {Text(LocalizedStringKey(text)).font(.system(.caption2,design:.monospaced,weight:.semibold)).foregroundStyle(color).padding(.horizontal,9).padding(.vertical,5).background(color.opacity(0.1),in:Capsule())}
}
struct SmallHeading: View {
    let text: LocalizedStringKey
    var body: some View {Text(text).font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(Color.muted)}
}
struct ScrollableForLargeType:ViewModifier {
    @Environment(\.dynamicTypeSize) private var size
    @ViewBuilder func body(content:Content)->some View {
        if size.isAccessibilitySize{ScrollView(.vertical){content}}else{content}
    }
}
