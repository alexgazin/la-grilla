import SwiftUI
import MusicDomain
struct MixerView: View {
    @Bindable var session: Session
    @Environment(\.dynamicTypeSize) private var dynamicType
    var body:some View{Group{if dynamicType.isAccessibilitySize{accessibleMixer}else{standardMixer}}}
    var standardMixer: some View {
        ScrollView(.vertical,showsIndicators:false) {
        VStack(alignment:.leading,spacing:16){
            HStack{VStack(alignment:.leading,spacing:6){SmallHeading(text:"MIXING DESK");Text("Find your balance.").font(.system(size:22,weight:.medium))};Spacer();CapsuleLabel(text:"STEREO",color:.mint)}.padding(.top,20)
            HStack(alignment:.top,spacing:8){
                ScrollView(.horizontal){HStack(spacing:8){ForEach(Array(session.displayProject.tracks.enumerated()),id:\.element.id){i,t in channel(index:i,track:t,height:430).frame(width:108)}}}.scrollIndicators(.visible)
                channel(index:masterBus,track:nil,height:430).frame(width:78)
            }.frame(height:430)
            HStack(alignment:.top,spacing:10){Image(systemName:"headphones").foregroundStyle(Color.mint);Text("A little space goes a long way.\nKeep the master below the red.").font(.system(size:12)).foregroundStyle(Color.muted).lineSpacing(4)}.padding(.top,4)
            Spacer(minLength:0)
        }.padding(.horizontal,18).padding(.bottom,18).disabled(session.performance.replaying)
        }
    }
    private var accessibleMixer:some View {Form {
        ForEach(Array(session.displayProject.tracks.enumerated()),id:\.element.id){index,track in
            SwiftUI.Section(track.displayName){
                Text(String(format:"%.1f dB",track.gain)).font(.headline.monospaced())
                Slider(value:Binding(get:{session.displayProject.tracks[index].gain},set:{setGain(index,$0)}),in:-61...6,step:1,onEditingChanged:{_ in session.mixerGesture=false}).accessibilityLabel("Gain \(track.displayName)")
                Slider(value:Binding(get:{session.displayProject.tracks[index].pan},set:{value in session.mixerEdit{$0.tracks[index].pan=value}}),in:-1...1,onEditingChanged:{_ in session.mixerGesture=false}).accessibilityLabel("Pan \(track.displayName)")
                Toggle("Mute",isOn:Binding(get:{session.displayProject.tracks[index].mute},set:{value in session.mixerImmediate{$0.tracks[index].mute=value}}))
                Toggle("Solo",isOn:Binding(get:{session.displayProject.tracks[index].solo},set:{value in session.mixerImmediate{$0.tracks[index].solo=value}}))
            }
        }
        SwiftUI.Section("Master"){
            Text(String(format:"%.1f dB",session.displayProject.master)).font(.headline.monospaced())
            Slider(value:Binding(get:{session.displayProject.master},set:{setGain(masterBus,$0)}),in:-61...6,step:1,onEditingChanged:{_ in session.mixerGesture=false}).accessibilityLabel("Master gain")
        }
    }.tint(.mint).disabled(session.performance.replaying)}
    func channel(index: Int,track: Track?,height: CGFloat)->some View {
        let color: Color = track.map{Color.track($0.role)} ?? .mint
        let gain=track?.gain ?? session.displayProject.master
        return VStack(spacing:12){
            RoundedRectangle(cornerRadius:2).fill(color).frame(height:3)
            Text(track?.displayName ?? NSLocalizedString("Master",comment:"Master channel")).font(.system(size:11,weight:.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(LocalizedStringKey(gain<=(-61) ? "−∞":String(format:"%.1f",gain))).font(.system(size:14,weight:.medium,design:.monospaced)).foregroundStyle(color).onTapGesture{session.mixerGesture=false;setGain(index,0);session.mixerGesture=false}.accessibilityLabel("\(gain) decibels. Tap to reset.")
            GeometryReader{geo in
                let h=max(60,geo.size.height-22)
                ZStack(alignment:.top){
                    Rectangle().fill(Color.ink).frame(width:5,height:h).offset(y:11)
                    ForEach(0..<7){i in HStack{Rectangle().fill(Color.muted.opacity(0.25)).frame(width:5,height:1);Spacer();Rectangle().fill(Color.muted.opacity(0.25)).frame(width:5,height:1)}.padding(.horizontal,5).offset(y:CGFloat(i)*h/6+11)}
                    Rectangle().fill(Color.mint.opacity(0.65)).frame(width:3,height:h*CGFloat(min(1,session.audio.meters[index]))).frame(height:h,alignment:.bottom).offset(x:13,y:11)
                    RoundedRectangle(cornerRadius:5).fill(Color.muted).frame(width:35,height:23).overlay{Rectangle().fill(Color.ink).frame(width:23,height:2)}.offset(y:(1-CGFloat((gain+61)/67))*h)
                }.frame(maxWidth:.infinity,maxHeight:.infinity).contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged{v in let value=Double(1-min(1,max(0,(v.location.y-11)/h)))*67-61;setGain(index,value)}.onEnded{_ in session.mixerGesture=false}).accessibilityElement().accessibilityLabel(track?.displayName ?? NSLocalizedString("Master",comment:"Master channel")).accessibilityValue("\(Int(gain)) dB").accessibilityAdjustableAction{direction in session.mixerGesture=false;setGain(index,min(6,max(-61,gain+(direction == .increment ? 1:-1))));session.mixerGesture=false}
            }
            Text("dB").font(.system(size:9,design:.monospaced)).foregroundStyle(Color.muted)
            if let track {
                Slider(value:Binding(get:{session.displayProject.tracks[index].pan},set:{v in session.mixerEdit{$0.tracks[index].pan=v}}),in:-1...1,onEditingChanged:{_ in session.mixerGesture=false}).tint(color).accessibilityLabel("Pan \(track.displayName)")
                HStack(spacing:4){Button{session.mixerImmediate{$0.tracks[index].mute.toggle()}}label:{Text("M").frame(maxWidth:.infinity,minHeight:44).background(track.mute ? color.opacity(0.3):Color.ink,in:RoundedRectangle(cornerRadius:5))}.accessibilityLabel("Mute \(track.displayName)").accessibilityValue(track.mute ? "On":"Off");Button{session.mixerImmediate{$0.tracks[index].solo.toggle()}}label:{Text("S").frame(maxWidth:.infinity,minHeight:44).background(track.solo ? color.opacity(0.3):Color.ink,in:RoundedRectangle(cornerRadius:5))}.accessibilityLabel("Solo \(track.displayName)").accessibilityValue(track.solo ? "On":"Off")}.font(.system(size:11,weight:.semibold)).foregroundStyle(color).buttonStyle(.plain)
            }else{Text("L  ·  R").font(.system(size:9,design:.monospaced)).foregroundStyle(Color.muted).frame(height:31);CapsuleLabel(text:session.audio.meters[masterBus]>=0.98 ? "CLIP":"OUT",color:session.audio.meters[masterBus]>=0.98 ? .record:.mint).frame(height:38)}
        }.padding(.horizontal,9).padding(.vertical,12).frame(maxWidth:.infinity).frame(height:height).background(Color.panel,in:RoundedRectangle(cornerRadius:10))
    }
    func setGain(_ index: Int,_ value: Double){session.mixerEdit{p in if index==masterBus{p.master=value}else{p.tracks[index].gain=value}}}
}
