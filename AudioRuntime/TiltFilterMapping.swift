import Foundation

/// A relative, bounded gesture. Its clock is the motion sensor's monotonic timestamp.
/// Starting or calibrating adopts the current filter; neither operation sends a value.
struct TiltFilterMapping {
    private(set) var baseline:Double
    private(set) var deflection=0.0
    private(set) var value:Double
    private(set) var calibrated=false
    private var neutral:Double?
    private var previousTime:Double?
    private var emittedAt:Double?
    private var emittedValue:Double
    private static let deadZone=0.03
    private static let fullTravel=Double.pi/6
    private static let maximumModulation=0.65
    private static let smoothingSeconds=0.12
    private static let outputInterval=1.0/15.0

    init(filter:Double){
        let initial=filter.isFinite ? min(1,max(-1,filter)):0
        baseline=initial;value=initial;emittedValue=initial
    }

    mutating func calibrate(angle:Double,filter:Double){
        guard angle.isFinite,filter.isFinite else{return}
        self=Self(filter:filter)
        neutral=angle;calibrated=true
    }

    /// Returns only a changed value that is eligible for actual audio delivery.
    mutating func sample(angle:Double,time:Double)->Double? {
        guard angle.isFinite,time.isFinite,time>=0 else{return nil}
        if let previousTime, time<=previousTime{return nil}
        guard let neutral else{
            self.neutral=angle;calibrated=true;previousTime=time;emittedAt=time
            return nil
        }
        guard let previousTime else{
            self.previousTime=time;emittedAt=time
            return nil
        }
        let dt=min(0.25,time-previousTime)
        self.previousTime=time
        // A device angle crossing ±π stays a small physical movement.
        let delta=atan2(sin(angle-neutral),cos(angle-neutral))
        let magnitude=min(1,max(0,(abs(delta)-Self.deadZone)/(Self.fullTravel-Self.deadZone)))
        deflection=delta<0 ? -magnitude:magnitude
        let target=min(1,max(-1,baseline+deflection*Self.maximumModulation))
        value+=(target-value)*(1-exp(-dt/Self.smoothingSeconds))
        guard time-(emittedAt ?? time)>=Self.outputInterval,
              abs(value-emittedValue)>=0.003 else{return nil}
        emittedAt=time;emittedValue=value
        return value
    }
}
