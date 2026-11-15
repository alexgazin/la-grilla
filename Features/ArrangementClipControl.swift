import SwiftUI
import UIKit
import Observation

@MainActor @Observable final class ArrangementDragDiagnostics {
    static let shared=ArrangementDragDiagnostics()
    static let enabled=ProcessInfo.processInfo.arguments.contains("--uitesting")
    private(set) var value=""
    @ObservationIgnored private var events:[String]=[]
    static func record(_ event:@autoclosure()->String){
        guard enabled else{return}
        let message="\(ProcessInfo.processInfo.systemUptime) \(event().prefix(512))"
        shared.events.append(message)
        if shared.events.count>16{shared.events.removeFirst(shared.events.count-16)}
        shared.value=shared.events.joined(separator:"\n")
        print("LA_GRILLA_DRAG "+message)
    }
}

/// The existing heading exposes bounded QA data without drawing a debug overlay
/// or invalidating the clip gesture hosts when diagnostics change.
struct ArrangementDragTraceValue:ViewModifier {
    @ViewBuilder
    func body(content:Content)->some View {
        if ArrangementDragDiagnostics.enabled {
            content.accessibilityIdentifier("grid.drag-diagnostics")
                .accessibilityValue(Text(verbatim:ArrangementDragDiagnostics.shared.value))
        }else{content}
    }
}

enum ArrangementClipTouchLayout {
    nonisolated static func resizeCorner(in bounds:CGRect)->CGRect? {
        // Dense clips keep their whole body for dragging; the inspector offers
        // resize controls. Short lanes reserve their center for moving too.
        guard bounds.width>=88,bounds.height>=44 else{return nil}
        let side:CGFloat=bounds.height<88 ? floor(bounds.height/2)-4:44
        return CGRect(x:bounds.maxX-side,y:bounds.maxY-side,width:side,height:side)
    }
}

private enum ArrangementClipProvider {
    /// Foundation can invoke this loader on a background queue. Construct it in
    /// a nonisolated context and capture only immutable, Sendable UTF-8 bytes.
    nonisolated static func make(_ payload:String)->NSItemProvider {
        let data=Data(payload.utf8),provider=NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier:"public.utf8-plain-text",visibility:.all){ @Sendable [data] completion in
            completion(data,nil);return nil
        }
        return provider
    }
}

/// One bounded native surface owns clip touches and accessibility. SwiftUI
/// draws the face beneath it; the system still performs the actual drag/drop.
struct ArrangementClipControl:UIViewRepresentable {
    let label:String
    let value:String
    let hint:String
    let identifier:String
    let enabled:Bool
    let makePayload:(CGPoint)->String?
    let resize:(UIGestureRecognizer.State,CGFloat)->Void
    let activate:()->Void
    func makeUIView(context:Context)->ArrangementClipControlView{ArrangementClipControlView(frame:.zero)}
    func updateUIView(_ view:ArrangementClipControlView,context:Context){
        view.accessibilityLabel=label;view.accessibilityValue=value;view.accessibilityHint=hint;view.accessibilityIdentifier=identifier
        view.accessibilityTraits=enabled ? .button:[.button,.notEnabled]
        view.acceptsInput=enabled;view.isUserInteractionEnabled=enabled
        view.makePayload=makePayload;view.resize=resize;view.activate=activate
    }
}

final class ArrangementClipControlView:UIView,UIGestureRecognizerDelegate,UIDragInteractionDelegate {
    var acceptsInput=true
    var makePayload:((CGPoint)->String?)?
    var resize:((UIGestureRecognizer.State,CGFloat)->Void)?
    var activate:(()->Void)?
    private let resizePan=UIPanGestureRecognizer()
    private let tap=UITapGestureRecognizer()
    private var initialTouchPoint:CGPoint?
    private var dragInFlight=false
    private func isResizePoint(_ point:CGPoint)->Bool{ArrangementClipTouchLayout.resizeCorner(in:bounds)?.contains(point) ?? false}
    override init(frame:CGRect){super.init(frame:frame);configure()}
    required init?(coder:NSCoder){super.init(coder:coder);configure()}
    private func configure(){
        backgroundColor = .clear;isOpaque=false;isAccessibilityElement=true
        resizePan.maximumNumberOfTouches=1;resizePan.delegate=self
        resizePan.addTarget(self,action:#selector(resized(_:)));addGestureRecognizer(resizePan)
        tap.delegate=self;tap.addTarget(self,action:#selector(tapped));tap.require(toFail:resizePan);addGestureRecognizer(tap)
        let drag=UIDragInteraction(delegate:self);drag.isEnabled=true;addInteraction(drag)
    }
    override var accessibilityFrame:CGRect {
        get{UIAccessibility.convertToScreenCoordinates(bounds,in:self)}
        set{super.accessibilityFrame=newValue}
    }
    override func accessibilityActivate()->Bool {
        guard acceptsInput,let activate else{return false};activate();return true
    }
    @objc private func tapped(){
        ArrangementDragDiagnostics.record("tap id=\(accessibilityIdentifier ?? "unknown") dragInFlight=\(dragInFlight)")
        initialTouchPoint=nil
        _ = accessibilityActivate()
    }
    @objc private func resized(_ recognizer:UIPanGestureRecognizer){
        // Window coordinates stay fixed while SwiftUI changes the clip width.
        resize?(recognizer.state,recognizer.translation(in:window).x)
        if [.ended,.cancelled,.failed].contains(recognizer.state){initialTouchPoint=nil}
    }
    func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldReceive touch:UITouch)->Bool {
        guard acceptsInput else{return false}
        if gestureRecognizer === tap,!dragInFlight {
            // UIKit instantiates a drag session after finger movement. Its
            // location(in:) is the current point, not this original grip.
            initialTouchPoint=touch.location(in:self)
            ArrangementDragDiagnostics.record("touchdown id=\(accessibilityIdentifier ?? "unknown") point=\(String(describing:initialTouchPoint)) touchTime=\(touch.timestamp) bounds=\(bounds)")
        }
        return gestureRecognizer !== resizePan || isResizePoint(touch.location(in:self))
    }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer:UIGestureRecognizer)->Bool {
        guard acceptsInput else{return false}
        if gestureRecognizer === resizePan{let velocity=resizePan.velocity(in:window);return abs(velocity.x)>=abs(velocity.y)}
        return true
    }
    func dragInteraction(_ interaction:UIDragInteraction,itemsForBeginning session:UIDragSession)->[UIDragItem] {
        let current=session.location(in:self)
        ArrangementDragDiagnostics.record("items id=\(accessibilityIdentifier ?? "unknown") current=\(current) initial=\(String(describing:initialTouchPoint))")
        guard acceptsInput,let point=initialTouchPoint,bounds.contains(point),!isResizePoint(point)else{
            ArrangementDragDiagnostics.record("items rejected input=\(acceptsInput) initial=\(String(describing:initialTouchPoint)) bounds=\(bounds)")
            return []
        }
        guard let payload=makePayload?(point)else{ArrangementDragDiagnostics.record("items rejected payload id=\(accessibilityIdentifier ?? "unknown")");return []}
        // This is String's native Transferable representation. There is no
        // NSString bridge. The revision is fresh; only this touch's original
        // grip is retained while UIKit instantiates the drag session.
        return [UIDragItem(itemProvider:ArrangementClipProvider.make(payload))]
    }
    func dragInteraction(_ interaction:UIDragInteraction,sessionWillBegin session:UIDragSession){
        dragInFlight=true
        ArrangementDragDiagnostics.record("willBegin id=\(accessibilityIdentifier ?? "unknown") current=\(session.location(in:self)) initial=\(String(describing:initialTouchPoint))")
    }
    func dragInteraction(_ interaction:UIDragInteraction,session:UIDragSession,willEndWith operation:UIDropOperation){
        ArrangementDragDiagnostics.record("willEnd id=\(accessibilityIdentifier ?? "unknown") operation=\(operation.rawValue) current=\(session.location(in:self))")
    }
    func dragInteraction(_ interaction:UIDragInteraction,session:UIDragSession,didEndWith operation:UIDropOperation){
        ArrangementDragDiagnostics.record("didEnd id=\(accessibilityIdentifier ?? "unknown") operation=\(operation.rawValue) current=\(session.location(in:self))")
        dragInFlight=false;initialTouchPoint=nil
    }
    func dragInteraction(_ interaction:UIDragInteraction,sessionAllowsMoveOperation session:UIDragSession)->Bool{true}
    func dragInteraction(_ interaction:UIDragInteraction,previewForLifting item:UIDragItem,session:UIDragSession)->UITargetedDragPreview? {
        guard let window else{return nil}
        var rect=convert(bounds,to:window).intersection(window.bounds)
        var parent=superview
        while let view=parent {
            if view.clipsToBounds{rect=rect.intersection(view.convert(view.bounds,to:window))}
            parent=view.superview
        }
        guard !rect.isNull,!rect.isEmpty else{return nil}
        ArrangementDragDiagnostics.record("preview id=\(accessibilityIdentifier ?? "unknown") rect=\(rect)")
        let format=UIGraphicsImageRendererFormat();format.scale=window.screen.scale
        let image=UIGraphicsImageRenderer(size:rect.size,format:format).image{context in
            context.cgContext.translateBy(x:-rect.minX,y:-rect.minY)
            _ = window.drawHierarchy(in:window.bounds,afterScreenUpdates:false)
        }
        let preview=UIImageView(image:image);preview.frame=CGRect(origin:.zero,size:rect.size)
        let parameters=UIDragPreviewParameters();parameters.backgroundColor = .clear
        parameters.visiblePath=UIBezierPath(roundedRect:preview.bounds,cornerRadius:11)
        let target=UIDragPreviewTarget(container:window,center:CGPoint(x:rect.midX,y:rect.midY))
        return UITargetedDragPreview(view:preview,parameters:parameters,target:target)
    }
}
