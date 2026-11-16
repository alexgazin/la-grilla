import SwiftUI
import MusicDomain
import UIKit
extension Color {
    private static func adaptive(_ dark:UInt32,_ light:UInt32,contrastDark:UInt32?=nil,contrastLight:UInt32?=nil)->Color {
        Color(uiColor:UIColor{trait in let high=trait.accessibilityContrast == .high;let hex=trait.userInterfaceStyle == .dark ? (high ? contrastDark ?? dark:dark):(high ? contrastLight ?? light:light);return UIColor(red:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1)})
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
    static let outline=adaptive(0x414A3A,0xD0D8C5,contrastDark:0xA3B990,contrastLight:0x4A6036)
    static func track(_ role: TrackRole) -> Color {role == .harmony ? .harmony : role == .drums ? .drums : role == .bass ? .bass : .mint}
}
struct IconButton: View {
    let symbol: String; let label: LocalizedStringKey; var color: Color = .primary; let action: () -> Void
    var body: some View {Button(action:action){Image(systemName:symbol).font(.system(size:18,weight:.medium)).foregroundStyle(color).frame(minWidth:44,minHeight:44).contentShape(Rectangle())}.buttonStyle(StudioQuietButtonStyle()).accessibilityLabel(label)}
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
    @Environment(\.colorSchemeContrast) private var contrast
    var color:Color = .panel
    init(color:Color = .panel){self.color=color}
    func body(content:Content)->some View {content.background(color,in:RoundedRectangle(cornerRadius:16,style:.continuous)).overlay{RoundedRectangle(cornerRadius:16,style:.continuous).stroke(Color.outline.opacity(contrast == .increased ? 1:0.65),lineWidth:contrast == .increased ? 1:0.6)}}
}
struct StudioActionStyle:ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var color:Color = .mint
    var prominent=true
    init(color:Color = .mint,prominent:Bool = true){self.color=color;self.prominent=prominent}
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.system(.subheadline,weight:.semibold)).foregroundStyle(prominent ? Color.ink:color)
            .frame(maxWidth:.infinity,minHeight:48).padding(.horizontal,12)
            .background(prominent ? color:Color.raised,in:RoundedRectangle(cornerRadius:14,style:.continuous))
            .opacity(!enabled ? 0.35:configuration.isPressed ? 0.76:1).scaleEffect(configuration.isPressed && !reduceMotion ? 0.98:1)
    }
}
struct StudioMark:View {
    var body:some View {Canvas{context,_ in
        for row in 0..<3 {
            let y=CGFloat(row)*8+5
            let segments:[(CGFloat,CGFloat,Color)]=row==1 ? [(2,8,.studioText),(15,5,.harmony),(21,9,.studioText)]:[(1,10,.studioText),(15,10,.studioText),(26,4,.harmony)]
            for (x,width,color) in segments{context.fill(Path(roundedRect:CGRect(x:x,y:y,width:width,height:4),cornerRadius:1),with:.color(color))}
        }
        context.fill(Path(roundedRect:CGRect(x:11,y:1,width:3,height:28),cornerRadius:1.5),with:.color(.mint))
    }.frame(width:30,height:30).accessibilityHidden(true)}
}

struct StudioSegments<Value:Equatable>:View {
    let title:LocalizedStringKey
    @Binding var selection:Value
    let options:[(Value,LocalizedStringKey)]
    var body:some View {HStack(spacing:3){ForEach(options.indices,id:\.self){index in
        Button{selection=options[index].0}label:{Text(options[index].1).font(.system(.caption,weight:.semibold)).lineLimit(2).minimumScaleFactor(1).frame(maxWidth:.infinity,minHeight:44).foregroundStyle(selection==options[index].0 ? Color.ink:Color.muted).background(selection==options[index].0 ? Color.mint:Color.clear,in:RoundedRectangle(cornerRadius:11,style:.continuous))}.buttonStyle(StudioQuietButtonStyle()).accessibilityAddTraits(selection==options[index].0 ? .isSelected:[])
    }}.padding(3).modifier(StudioSurface()).accessibilityElement(children:.contain).accessibilityLabel(title)}
}

struct StudioQuietButtonStyle:ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    init(){}
    func makeBody(configuration:Configuration)->some View {configuration.label.contentShape(Rectangle()).opacity(!enabled ? 0.35:configuration.isPressed ? 0.6:1)}
}
struct StudioNavigationSurface:ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    init(){}
    @ViewBuilder func body(content:Content)->some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0,*),!reduceTransparency{content.glassEffect(.regular,in:RoundedRectangle(cornerRadius:20,style:.continuous))}
        else{content.modifier(StudioSurface())}
        #else
        // Older local Xcode toolchains do not include the iOS 26 glass API.
        // Keep the same surface already used when running on iOS 18.
        content.modifier(StudioSurface())
        #endif
    }
}
