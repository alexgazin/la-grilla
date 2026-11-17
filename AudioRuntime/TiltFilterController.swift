import Foundation
import CoreMotion
import Observation

/// Keeps CMMotionManager cleanup independent of a global-actor deinitializer.
private final class TiltMotionSource {
    let manager=CMMotionManager()
    deinit{manager.stopDeviceMotionUpdates()}
}

@MainActor @Observable final class TiltFilterController {
    enum Axis:Sendable {case portrait,portraitInverted,landscapeLeft,landscapeRight}
    private(set) var active=false
    private(set) var calibrating=false
    private(set) var deflection=0.0
    private(set) var notice:String?
    @ObservationIgnored private let source=TiltMotionSource()
    @ObservationIgnored private var generation=0
    @ObservationIgnored private var mapping=TiltFilterMapping(filter:0)
    @ObservationIgnored private var latestAngle:Double?
    @ObservationIgnored private var latestTimestamp:Double?
    @ObservationIgnored private var lastVisualTime=0.0
    @ObservationIgnored private var delivery:(@MainActor (Double)->Void)?
    @ObservationIgnored private var readiness:Task<Void,Never>?
    var available:Bool{source.manager.isDeviceMotionAvailable}

    func start(filter:Double,axis:Axis,delivery:@escaping @MainActor (Double)->Void){
        stop()
        guard available,CMMotionManager.availableAttitudeReferenceFrames().contains(.xArbitraryZVertical) else{
            notice="Tilt is unavailable on this device.";return
        }
        guard filter.isFinite else{notice="Tilt stopped. You can enable it again.";return}
        generation+=1;let token=generation
        mapping=TiltFilterMapping(filter:filter);latestAngle=nil;latestTimestamp=nil;lastVisualTime=0
        self.delivery=delivery;notice=nil;active=true;calibrating=true;deflection=0
        source.manager.deviceMotionUpdateInterval=1.0/30.0
        source.manager.showsDeviceMovementDisplay=false
        source.manager.startDeviceMotionUpdates(using:.xArbitraryZVertical,to:.main){[weak self] motion,error in
            // CMDeviceMotion and Error never cross into the Sendable task.
            let component:Double?
            switch axis {
            case .portrait:component=motion?.gravity.x
            case .portraitInverted:component=motion.map{-$0.gravity.x}
            case .landscapeLeft:component=motion.map{-$0.gravity.y}
            case .landscapeRight:component=motion?.gravity.y
            }
            // Gravity is stable when the phone is upright; Euler roll is not.
            let angle=component.map{$0.isFinite ? asin(min(1,max(-1,$0))):Double.nan}
            let time=motion?.timestamp,failed=error != nil
            Task{@MainActor [weak self] in
                guard let self,self.active,self.generation==token else{return}
                if failed{self.stop();self.notice="Tilt stopped. You can enable it again.";return}
                guard let angle,let time,angle.isFinite,time.isFinite else{return}
                self.receive(angle:angle,time:time)
            }
        }
        readiness=Task{@MainActor [weak self] in
            do{try await Task.sleep(for:.seconds(3))}catch{return}
            guard let self,self.active,self.calibrating,self.generation==token else{return}
            self.stop();self.notice="Tilt stopped. You can enable it again."
        }
    }

    func calibrate(filter:Double){
        guard active,let latestAngle else{return}
        mapping.calibrate(angle:latestAngle,filter:filter);deflection=0;notice=nil
    }

    func stop(notice:String?=nil){
        generation+=1;source.manager.stopDeviceMotionUpdates()
        readiness?.cancel();readiness=nil;delivery=nil;active=false;calibrating=false
        latestAngle=nil;latestTimestamp=nil;deflection=0;self.notice=notice
    }

    private func receive(angle:Double,time:Double){
        guard time>=0,latestTimestamp.map({time>$0}) ?? true else{return}
        latestTimestamp=time
        latestAngle=angle
        let output=mapping.sample(angle:angle,time:time)
        if calibrating,mapping.calibrated{calibrating=false;readiness?.cancel();readiness=nil}
        if time-lastVisualTime>=1.0/15.0{lastVisualTime=time;deflection=mapping.deflection}
        if let output{delivery?(output)}
    }
}
