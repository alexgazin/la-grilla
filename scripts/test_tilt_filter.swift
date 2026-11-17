import Foundation

/// Run with TiltFilterMapping.swift. These are physical-input contracts, not
/// evidence of real sensors, CoreMotion permission or audio latency on a phone.
@main struct TiltFilterChecks {
    static func require(_ condition:@autoclosure ()->Bool,_ message:String){
        precondition(condition(),message)
    }
    static func main(){
        var checks=0
        var held=TiltFilterMapping(filter:0.42)
        require(held.sample(angle:0.7,time:0)==nil,"Starting must adopt the held orientation without an FX write")
        for n in 1...300 {
            let noise=0.7+(n.isMultiple(of:2) ? 0.02:-0.02)
            require(held.sample(angle:noise,time:Double(n)/30)==nil,"Neutral hand tremor must stay silent")
        }
        require(held.value==0.42,"Enabling must hold the existing manual filter")
        checks+=1

        func response(rate:Int)->Double{
            var mapping=TiltFilterMapping(filter:0)
            _ = mapping.sample(angle:0,time:0)
            for n in 1...rate{_ = mapping.sample(angle:0.35,time:Double(n)/Double(rate))}
            return mapping.value
        }
        let thirty=response(rate:30),sixty=response(rate:60)
        require(thirty>0.2 && thirty<0.65,"A deliberate tilt must audibly change the target")
        require(abs(thirty-sixty)<0.01,"The same physical motion must not depend on sensor sample rate")
        checks+=1

        var wrapped=TiltFilterMapping(filter:0)
        _ = wrapped.sample(angle:179*Double.pi/180,time:0)
        for n in 1...30{_ = wrapped.sample(angle:-179*Double.pi/180,time:Double(n)/30)}
        require(wrapped.value>=0 && wrapped.value<0.03,"Crossing ±pi is a two-degree movement, not a full sweep")
        checks+=1

        for initial in [-0.9,0.9] {
            var mapping=TiltFilterMapping(filter:initial)
            _ = mapping.sample(angle:0,time:0)
            var outputs:[Double]=[]
            for n in 1...300 {
                let angle=n<=150 ? Double.pi/2:-Double.pi/2
                if let value=mapping.sample(angle:angle,time:Double(n)/30){outputs.append(value)}
            }
            require(outputs.allSatisfy{$0.isFinite && (-1...1).contains($0)},"Extreme movement must stay within the legal filter range")
            require(mapping.value>=initial-0.65-0.001 && mapping.value<=initial+0.65+0.001,"Tilt travel must remain relative to the manual baseline")
        }
        checks+=1

        var rateLimited=TiltFilterMapping(filter:0)
        _ = rateLimited.sample(angle:0,time:0)
        var emitted:[Double]=[]
        for n in 1...900 {
            let t=Double(n)/300
            if rateLimited.sample(angle:sin(t*8)*0.5,time:t) != nil{emitted.append(t)}
        }
        require(emitted.count>=15 && emitted.count<=45,"Control updates must remain responsive and bounded to15Hz")
        for pair in zip(emitted,emitted.dropFirst()){
            require(pair.1-pair.0>=1.0/15.0-1e-12,"No two actual deliveries may exceed the rate budget")
        }
        checks+=1

        let oldValue=rateLimited.value,oldDeflection=rateLimited.deflection
        for (angle,time) in [(Double.nan,4.0),(Double.infinity,4.0),(0.0,Double.nan),(0.0,Double.infinity),(0.0,-1.0),(0.0,3.0),(0.0,2.0)]{
            require(rateLimited.sample(angle:angle,time:time)==nil,"Invalid or stale sensor data must be ignored")
            require(rateLimited.value==oldValue && rateLimited.deflection==oldDeflection,"Rejected input must not mutate the gesture")
        }
        checks+=1

        rateLimited.calibrate(angle:0.25,filter:0.8)
        require(rateLimited.value==0.8 && rateLimited.deflection==0,"Calibration must adopt the actual current filter")
        for n in 1...60 {
            require(rateLimited.sample(angle:0.25,time:4+Double(n)/30)==nil,"Holding a newly calibrated neutral must not send a reset")
        }
        checks+=1

        var left=TiltFilterMapping(filter:0),right=TiltFilterMapping(filter:0)
        _ = left.sample(angle:0,time:0);_ = right.sample(angle:0,time:0)
        for n in 1...30{
            _ = left.sample(angle:-0.2,time:Double(n)/30)
            _ = right.sample(angle:0.2,time:Double(n)/30)
        }
        require(abs(left.value+right.value)<1e-10,"Equal left/right movement must give symmetric control")
        checks+=1

        // Volume uses the same gesture around zero as relative modulation.
        // Exercise that actual mapping; do not copy the View's dB formula here.
        var volumeDelta=TiltFilterMapping(filter:0)
        require(volumeDelta.sample(angle:0.2,time:0)==nil && volumeDelta.value==0,"Volume control must begin with no relative modulation")
        var volumeOutputs:[Double]=[]
        for n in 1...120 {
            let angle=n<=60 ? 1.2:-1.2
            if let output=volumeDelta.sample(angle:angle,time:Double(n)/30){volumeOutputs.append(output)}
        }
        require(volumeOutputs.contains{$0>0.1} && volumeOutputs.contains{$0 < -0.1},"Volume modulation must respond in both directions")
        require(volumeOutputs.allSatisfy{abs($0)<=0.65+1e-10},"A zero-centred gesture must preserve its defined modulation limit")
        checks+=1
        var recenteredVolume=TiltFilterMapping(filter:0)
        _ = recenteredVolume.sample(angle:0,time:0)
        for n in 1...30{_ = recenteredVolume.sample(angle:0.35,time:Double(n)/30)}
        require(recenteredVolume.value>0.1,"The gesture must be displaced before recalibration")
        recenteredVolume.calibrate(angle:0.35,filter:0)
        require(recenteredVolume.value==0,"Volume calibration must clear relative modulation")
        for n in 1...30 {
            require(recenteredVolume.sample(angle:0.35,time:2+Double(n)/30)==nil,"Holding the new neutral must not send relative modulation")
        }
        checks+=1
        print("Tilt filter physical-input contracts: \(checks) passed")
    }
}
