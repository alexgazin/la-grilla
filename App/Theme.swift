import SwiftUI
import MusicDomain
import UIKit
extension Color {
    private static func adaptive(_ dark:UInt32,_ light:UInt32)->Color {
        Color(uiColor:UIColor{trait in let hex=trait.userInterfaceStyle == .dark ? dark:light;return UIColor(red:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1)})
    }
    static let ink=adaptive(0x111510,0xF5F5EF)
    static let panel=adaptive(0x1A2018,0xFFFFFF)
    static let raised=adaptive(0x272E24,0xE8ECDD)
    static let muted=adaptive(0xB4BCAF,0x535D4C)
    static let mint=adaptive(0xD8F780,0x435D00)
    static let harmony=adaptive(0xEDBF7A,0x795000)
    static let drums=adaptive(0xA5ADFF,0x4749A2)
    static let bass=adaptive(0x86DCC6,0x00675A)
    static let record=adaptive(0xFF7B80,0xAA2D3D)
    static let studioText=adaptive(0xF1F2E8,0x192016)
    static let outline=adaptive(0x414A3A,0xD0D8C5)
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
    var body: some View {Text(text).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(Color.muted)}
}
struct ScrollableForLargeType:ViewModifier {
    @Environment(\.dynamicTypeSize) private var size
    @ViewBuilder func body(content:Content)->some View {
        if size.isAccessibilitySize{ScrollView(.vertical){content}}else{content}
    }
}
struct StudioQATypeSize:ViewModifier {
    @ViewBuilder func body(content:Content)->some View {
        if ProcessInfo.processInfo.arguments.contains("--large-type"){content.dynamicTypeSize(.accessibility3)}else{content}
    }
}

// Shared surfaces and actions keep the instrument's visual rhythm consistent.
struct StudioSurface:ViewModifier {
    var color:Color = .panel
    func body(content:Content)->some View {content.background(color,in:RoundedRectangle(cornerRadius:16)).overlay{RoundedRectangle(cornerRadius:16).stroke(Color.outline.opacity(0.65),lineWidth:0.6)}}
}
struct StudioActionStyle:ButtonStyle {
    var color:Color = .mint
    var prominent=true
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.system(.subheadline,weight:.semibold)).foregroundStyle(prominent ? Color.ink:color)
            .frame(maxWidth:.infinity,minHeight:48).padding(.horizontal,12)
            .background(prominent ? color:Color.raised,in:RoundedRectangle(cornerRadius:14))
            .opacity(configuration.isPressed ? 0.76:1).scaleEffect(configuration.isPressed ? 0.98:1)
    }
}
struct StudioMark:View {
    var body:some View {ZStack(alignment:.leading){VStack(spacing:5){ForEach(0..<3){index in RoundedRectangle(cornerRadius:1).fill(Color.mint.opacity(index==1 ? 1:0.45)).frame(width:24,height:3)}};RoundedRectangle(cornerRadius:1).fill(Color.mint).frame(width:3,height:28).offset(x:7)}.frame(width:30,height:30).accessibilityHidden(true)}
}
