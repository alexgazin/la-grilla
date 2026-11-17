import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import MusicDomain

/// All pads share one native input surface so scroll recognition and SwiftUI
/// view updates do not sit between a finger going down and the audio enqueue.
struct PadTouchSurface:UIViewRepresentable {
    let enabled:Bool
    let trace:Bool
    let onHit:(Int,TimeInterval)->Bool
    let onHeld:(Set<Int>)->Void
    func makeUIView(context:Context)->PadTouchView{PadTouchView()}
    func updateUIView(_ view:PadTouchView,context:Context){
        view.onHit=onHit;view.onHeld=onHeld;view.trace=trace
        view.isUserInteractionEnabled=enabled
        if !enabled{view.cancelTouches(notify:false)}
    }
    static func dismantleUIView(_ view:PadTouchView,coordinator:()){view.cancelTouches(notify:false);view.onHit=nil;view.onHeld=nil}
}

@MainActor final class PadTouchView:UIView {
    var onHit:((Int,TimeInterval)->Bool)?
    var onHeld:((Set<Int>)->Void)?
    var trace=false
    private var contacts:[ObjectIdentifier:Int]=[:]
    private var accepted=[Int](repeating:0,count:16)
    private var acceptedAt=[TimeInterval](repeating:0,count:16)
    private var releasedAt=[TimeInterval](repeating:0,count:16)
    private var elements:[PadAccessibilityElement]=[]
    private lazy var input=PadContactRecognizer(owner:self)
    override init(frame:CGRect){
        super.init(frame:frame)
        backgroundColor = .clear;isMultipleTouchEnabled=true;isAccessibilityElement=false
        addGestureRecognizer(input)
        elements=(0..<16).map{pad in
            let item=PadAccessibilityElement(accessibilityContainer:self)
            item.owner=self;item.pad=pad;item.accessibilityIdentifier="jam.pad.\(pad)"
            item.accessibilityLabel=NSLocalizedString(MusicDomain.Compiler.padNames[pad],comment:"Drum pad")
            item.accessibilityTraits = .button
            return item
        }
        accessibilityElements=elements
    }
    required init?(coder:NSCoder){fatalError("init(coder:) is unavailable")}
    private var cellWidth:CGFloat{max(0,(bounds.width-24)/4)}
    private var cellHeight:CGFloat{max(44,min(cellWidth,(bounds.height-24)/4))}
    private var top:CGFloat{(bounds.height-(4*cellHeight+24))/2}
    private func rect(_ pad:Int)->CGRect{CGRect(x:CGFloat(pad%4)*(cellWidth+8),y:top+CGFloat(pad/4)*(cellHeight+8),width:cellWidth,height:cellHeight)}
    override func layoutSubviews(){super.layoutSubviews();for pad in 0..<16{elements[pad].accessibilityFrameInContainerSpace=rect(pad)}}
    override func didMoveToWindow(){super.didMoveToWindow();if window==nil{cancelTouches(notify:false)}}
    func pad(at point:CGPoint)->Int?{(0..<16).first{rect($0).contains(point)}}
    func begin(_ touch:UITouch){
        let id=ObjectIdentifier(touch)
        guard contacts[id]==nil,let pad=pad(at:touch.location(in:self))else{return}
        contacts[id]=pad
        // Enqueue the sound before publishing visual/accessibility changes.
        if onHit?(pad,touch.timestamp)==true{accepted[pad]+=1;acceptedAt[pad]=ProcessInfo.processInfo.systemUptime}
        publishHeld()
    }
    func end(_ touches:Set<UITouch>){for touch in touches{if let pad=contacts.removeValue(forKey:ObjectIdentifier(touch)){releasedAt[pad]=touch.timestamp}};publishHeld()}
    var hasContacts:Bool{!contacts.isEmpty}
    func cancelTouches(notify:Bool=true){
        guard !contacts.isEmpty else{return}
        contacts.removeAll();if notify{publishHeld()}
        input.isEnabled=false;input.isEnabled=true
    }
    func cancelFromRecognizer(){guard !contacts.isEmpty else{return};contacts.removeAll();publishHeld()}
    private func publishHeld(){
        let held=Set(contacts.values)
        for pad in 0..<16{
            elements[pad].accessibilityValue=trace ? "accepted=\(accepted[pad]) held=\(held.contains(pad) ? 1:0) acceptedAt=\(acceptedAt[pad]) releasedAt=\(releasedAt[pad])":NSLocalizedString(held.contains(pad) ? "Pressed":"Ready",comment:"Drum pad state")
        }
        onHeld?(held)
    }
    func activate(_ pad:Int)->Bool{
        guard isUserInteractionEnabled,window != nil else{return false}
        let result=onHit?(pad,ProcessInfo.processInfo.systemUptime) ?? false
        if result{accepted[pad]+=1};publishHeld();return result
    }
}

@MainActor private final class PadAccessibilityElement:UIAccessibilityElement {
    weak var owner:PadTouchView?
    var pad=0
    override func accessibilityActivate()->Bool{owner?.activate(pad) ?? false}
}

@MainActor private final class PadContactRecognizer:UIGestureRecognizer {
    private weak var owner:PadTouchView?
    init(owner:PadTouchView){super.init(target:nil,action:nil);self.owner=owner;delaysTouchesBegan=false;delaysTouchesEnded=false;cancelsTouchesInView=false}
    override func canBePrevented(by preventingGestureRecognizer:UIGestureRecognizer)->Bool{false}
    override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent){
        guard let owner else{state = .failed;return}
        for touch in touches{owner.begin(touch)}
        if owner.hasContacts{state = state == .possible ? .began:.changed}else if state == .possible{state = .failed}
    }
    override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent){if state == .began || state == .changed{state = .changed}}
    override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent){owner?.end(touches);state = owner?.hasContacts == true ? .changed:.ended}
    override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent){owner?.cancelFromRecognizer();state = .cancelled}
    override func reset(){super.reset();owner?.cancelFromRecognizer()}
}
