import SwiftUI
import MusicDomain
struct MixerView: View {
    @Bindable var session: Session
    var body: some View {
        VStack(alignment:.leading,spacing:16){
            HStack{VStack(alignment:.leading,spacing:6){SmallHeading(text:"MIXING DESK");Text("Find your balance.").font(.system(size:22,weight:.medium))};Spacer();CapsuleLabel(text:"STEREO",color:.mint)}.padding(.top,20)
            GeometryReader{geo in
                HStack(alignment:.top,spacing:8){ForEach(Array(session.project.tracks.enumerated()),id:\.element.id){i,t in channel(index:i,track:t,height:geo.size.height)}
                    channel(index:3,track:nil,height:geo.size.height)
                }
            }.frame(minHeight:300,maxHeight:430)
            HStack(alignment:.top,spacing:10){Image(systemName:"headphones").foregroundStyle(Color.mint);Text("A little space goes a long way.\nKeep the master below the red.").font(.system(size:12)).foregroundStyle(Color.muted).lineSpacing(4)}.padding(.top,4)
            Spacer(minLength:0)
        }.padding(.horizontal,18).padding(.bottom,18)
    }
    func channel(index: Int,track: Track?,height: CGFloat)->some View {
        let color: Color = track.map{Color.track($0.role)} ?? .mint
        let gain=track?.gain ?? session.project.master
        return VStack(spacing:12){
            RoundedRectangle(cornerRadius:2).fill(color).frame(height:3)
            Text(track?.role.rawValue.capitalized ?? "Master").font(.system(size:11,weight:.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(gain<=(-61) ? "−∞":String(format:"%.1f",gain)).font(.system(size:14,weight:.medium,design:.monospaced)).foregroundStyle(color).onTapGesture{setGain(index,0)}.accessibilityLabel("\(gain) decibels. Tap to reset.")
            GeometryReader{geo in
                let h=max(60,geo.size.height-22)
                ZStack(alignment:.top){
                    Rectangle().fill(Color.ink).frame(width:5,height:h).offset(y:11)
                    ForEach(0..<7){i in HStack{Rectangle().fill(Color.muted.opacity(0.25)).frame(width:5,height:1);Spacer();Rectangle().fill(Color.muted.opacity(0.25)).frame(width:5,height:1)}.padding(.horizontal,5).offset(y:CGFloat(i)*h/6+11)}
                    Rectangle().fill(Color.mint.opacity(0.65)).frame(width:3,height:h*CGFloat(min(1,session.audio.meters[index]))).frame(height:h,alignment:.bottom).offset(x:13,y:11)
                    RoundedRectangle(cornerRadius:5).fill(Color(red:0.7,green:0.73,blue:0.78)).frame(width:35,height:23).overlay{Rectangle().fill(Color.ink).frame(width:23,height:2)}.offset(y:(1-CGFloat((gain+61)/67))*h)
                }.frame(maxWidth:.infinity,maxHeight:.infinity).contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged{v in let value=Double(1-min(1,max(0,(v.location.y-11)/h)))*67-61;setGain(index,value)}).accessibilityElement().accessibilityLabel(track?.role.rawValue ?? "Master").accessibilityValue("\(Int(gain)) dB").accessibilityAdjustableAction{direction in setGain(index,min(6,max(-61,gain+(direction == .increment ? 1:-1))))}
            }
            Text("dB").font(.system(size:9,design:.monospaced)).foregroundStyle(Color.muted)
            if let track {
                Slider(value:Binding(get:{session.project.tracks[index].pan},set:{v in session.edit{$0.tracks[index].pan=v}}),in:-1...1).tint(color).accessibilityLabel("Pan \(track.role.rawValue)")
                HStack(spacing:4){Button{session.edit{$0.tracks[index].mute.toggle()}}label:{Text("M").frame(maxWidth:.infinity,minHeight:38).background(track.mute ? color.opacity(0.3):Color.ink,in:RoundedRectangle(cornerRadius:5))};Button{session.edit{$0.tracks[index].solo.toggle()}}label:{Text("S").frame(maxWidth:.infinity,minHeight:38).background(track.solo ? color.opacity(0.3):Color.ink,in:RoundedRectangle(cornerRadius:5))}}.font(.system(size:11,weight:.semibold)).foregroundStyle(color).buttonStyle(.plain)
            }else{Text("L  ·  R").font(.system(size:9,design:.monospaced)).foregroundStyle(Color.muted).frame(height:31);CapsuleLabel(text:session.audio.meters[3]>=0.98 ? "CLIP":"OUT",color:session.audio.meters[3]>=0.98 ? .record:.mint).frame(height:38)}
        }.padding(.horizontal,9).padding(.vertical,12).frame(maxWidth:.infinity).frame(height:height).background(Color.panel,in:RoundedRectangle(cornerRadius:10))
    }
    func setGain(_ index: Int,_ value: Double){session.edit{p in if index==3{p.master=value}else{p.tracks[index].gain=value}}}
}
