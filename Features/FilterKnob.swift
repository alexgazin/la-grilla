import SwiftUI
import Foundation

/// A bipolar live filter. The top detent is bypass; left/right select LP/HP.
/// Gesture state is local, while the value always belongs to the audio controller.
struct FilterKnob:View {
    @Binding var value:Double
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var gestureActive=false
    @State private var dragging=false
    @State private var vertical=false
    @State private var lastAngle:Double?
    @State private var rawValue=0.0
    @State private var originValue=0.0

    init(value:Binding<Double>){_value=value}

    private var bounded:Double{value.isFinite ? min(1,max(-1,value)):0}
    private var readout:String{abs(bounded)<0.001 ? NSLocalizedString("BYPASS",comment:"Neutral filter"):String(format:"%+.0f%%",bounded*100)}
    private var accessibleReadout:String {
        abs(bounded)<0.001 ? readout:readout+" · "+NSLocalizedString(bounded<0 ? "LOW PASS":"HIGH PASS",comment:"Filter direction")
    }

    var body:some View {
        GeometryReader{geometry in
            let side=min(geometry.size.width,geometry.size.height)
            let center=CGPoint(x:geometry.size.width/2,y:geometry.size.height/2)
            ZStack {
                Canvas{context,_ in
                    let radius=side*0.38
                    context.stroke(arc(from:-225,to:45,center:center,radius:radius),with:.color(.outline),style:StrokeStyle(lineWidth:5,lineCap:.round))
                    let angle = -90+bounded*135
                    if abs(bounded)>0.001 {
                        context.stroke(arc(from:min(-90,angle),to:max(-90,angle),center:center,radius:radius),with:.color(.mint),style:StrokeStyle(lineWidth:5,lineCap:.round))
                    }
                    for step in -6...6 {
                        let tickAngle = -90+Double(step)*22.5
                        var tick=Path();tick.move(to:point(tickAngle,center:center,radius:radius+7));tick.addLine(to:point(tickAngle,center:center,radius:radius+(step==0 ? 12:10)))
                        context.stroke(tick,with:.color(step==0 ? .studioText:.muted.opacity(0.65)),style:StrokeStyle(lineWidth:step==0 ? 2:1,lineCap:.round))
                    }
                    let disc=CGRect(x:center.x-side*0.33,y:center.y-side*0.33,width:side*0.66,height:side*0.66)
                    context.fill(Path(ellipseIn:disc),with:.color(.raised))
                    context.stroke(Path(ellipseIn:disc),with:.color(.outline.opacity(0.8)),lineWidth:0.7)
                    var pointer=Path();pointer.move(to:point(angle,center:center,radius:side*0.24));pointer.addLine(to:point(angle,center:center,radius:side*0.29))
                    context.stroke(pointer,with:.color(.mint),style:StrokeStyle(lineWidth:3,lineCap:.round))
                }.accessibilityHidden(true)
                Text(readout).font(StudioTypography.value.weight(.semibold)).minimumScaleFactor(0.7).lineLimit(1).foregroundStyle(Color.studioText).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .highPriorityGesture(turn(center:center,side:side))
            .simultaneousGesture(TapGesture(count:2).onEnded{if enabled{value=0;Luz.Haptics.selection()}})
            .scaleEffect(dragging && !reduceMotion ? 1.015:1)
            .animation(reduceMotion || dragging ? nil:.easeOut(duration:0.12),value:bounded)
        }
        .frame(height:112)
        .opacity(enabled ? 1:0.35)
        .onChange(of:gestureActive){_,active in if !active{dragging=false;lastAngle=nil}}
        .onChange(of:enabled){_,active in if !active{dragging=false;lastAngle=nil}}
        .onDisappear{dragging=false;lastAngle=nil}
        .accessibilityRepresentation {
            Slider(value:$value,in:-1...1,step:0.01)
                .frame(maxWidth:.infinity,minHeight:112)
                .accessibilityLabel("Master filter")
                .accessibilityValue(Text(accessibleReadout))
                .accessibilityIdentifier("perform.filter")
                .accessibilityAction(named:Text("Reset master filter")){if enabled{value=0}}
                .disabled(!enabled)
        }
    }

    private func turn(center:CGPoint,side:CGFloat)->some Gesture {
        DragGesture(minimumDistance:0).updating($gestureActive){_,active,_ in active=true}.onChanged{event in
            guard enabled else{return}
            if !dragging {
                dragging=true;rawValue=bounded;originValue=bounded
                let start=event.startLocation
                vertical=hypot(Double(start.x-center.x),Double(start.y-center.y))<Double(side)*0.2
                lastAngle=atan2(Double(start.y-center.y),Double(start.x-center.x))
            }
            if vertical {
                rawValue=min(1,max(-1,originValue-Double(event.translation.height)/100))
            }else{
                let location=event.location
                guard hypot(Double(location.x-center.x),Double(location.y-center.y))>=Double(side)*0.16 else{lastAngle=nil;return}
                let angle=atan2(Double(location.y-center.y),Double(location.x-center.x))
                if let previous=lastAngle {
                    var delta=angle-previous
                    if delta>Double.pi{delta-=2*Double.pi}
                    if delta < -Double.pi{delta+=2*Double.pi}
                    // Clamp each delta so reversing at either end responds at once.
                    rawValue=min(1,max(-1,rawValue+delta*180/Double.pi/135))
                }
                lastAngle=angle
            }
            let next=abs(rawValue)<0.02 ? 0:rawValue
            // Luz detent: entering bypass ticks once.
            if next==0 && value != 0{Luz.Haptics.selection()}
            value=next
        }.onEnded{_ in dragging=false;lastAngle=nil}
    }

    private func point(_ degrees:Double,center:CGPoint,radius:CGFloat)->CGPoint {
        let angle=degrees*Double.pi/180
        return CGPoint(x:center.x+CGFloat(cos(angle))*radius,y:center.y+CGFloat(sin(angle))*radius)
    }
    private func arc(from:Double,to:Double,center:CGPoint,radius:CGFloat)->Path {
        var path=Path();path.move(to:point(from,center:center,radius:radius))
        let segments=max(1,Int(abs(to-from)/3))
        for step in 1...segments{path.addLine(to:point(from+(to-from)*Double(step)/Double(segments),center:center,radius:radius))}
        return path
    }
}
