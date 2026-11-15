import Foundation
import CoreMIDI
import AudioDSP

/// Core MIDI sends happen on this serial worker, never in the audio callback.
/// Events carry their destination generation; stale queued notes cannot reach a
/// newly selected endpoint. No incoming MIDI is forwarded to output.
final class MIDIOutputWorker:@unchecked Sendable {
    private let hub:MIDIHubHandle
    private let port:MIDIPortRef
    private let queue=DispatchQueue(label:"LaGrilla.MIDIOutput",qos:.userInteractive)
    private var timer:DispatchSourceTimer?
    private var destination=MIDIEndpointRef()
    private var epoch:UInt32=0
    private var buffer=[LGMIDIOutput](repeating:LGMIDIOutput(),count:512)
    private var failed=false
    init(hub:MIDIHubHandle,port:MIDIPortRef){
        self.hub=hub;self.port=port

    }
    private func startTimer(){
        guard timer==nil else{return};let timer=DispatchSource.makeTimerSource(queue:queue);timer.schedule(deadline:.now(),repeating:.milliseconds(1),leeway:.microseconds(100));timer.setEventHandler{[weak self] in self?.drain()};timer.resume();self.timer=timer
    }
    deinit{timer?.cancel();if port != 0{MIDIPortDispose(port)}}
    func select(_ endpoint:MIDIEndpointRef,channels:[Int32]){
        // Called for an endpoint change or an explicit retry, never for track
        // reordering. The hub overlays the latest audio-owned project channels
        // if a snapshot was adopted while this asynchronous selection waited.
        // Invalidate the old destination immediately. An in-flight render buffer
        // can still publish its old epoch; the worker will discard those events.
        let request=lg_midi_output_configure(hub.pointer,nil,0,0)
        queue.async{ [self] in
            if destination != 0{releaseAll()}
            while buffer.withUnsafeMutableBufferPointer({lg_midi_output_pop(hub.pointer,$0.baseAddress,Int32($0.count))})>0{}
            destination=0;failed=false
            let selected=channels.withUnsafeBufferPointer{lg_midi_output_activate(hub.pointer,request,$0.baseAddress,Int32($0.count),endpoint==0 ? 0:1)}
            guard selected != 0 else{epoch=0;timer?.cancel();timer=nil;return}
            destination=endpoint;epoch=selected
            if endpoint==0{timer?.cancel();timer=nil}else{startTimer()}
        }
    }
    /// Complete note release before iOS can suspend the process. This is called
    /// on MainActor, never from an audio/MIDI callback or the output queue.
    func suspend(){
        _ = lg_midi_output_configure(hub.pointer,nil,0,0)
        queue.sync {
            if destination != 0{releaseAll()}
            while buffer.withUnsafeMutableBufferPointer({lg_midi_output_pop(hub.pointer,$0.baseAddress,Int32($0.count))})>0{}
            destination=0;timer?.cancel();timer=nil
        }
    }
    private func send(time:UInt64,status:Int32,a:Int32,b:Int32)->OSStatus {
        var list=MIDIPacketList();return withUnsafeMutablePointer(to:&list){pointer in
            let packet=MIDIPacketListInit(pointer);let bytes=[UInt8(status),UInt8(a),UInt8(b)]
            _ = bytes.withUnsafeBufferPointer{MIDIPacketListAdd(pointer,MemoryLayout<MIDIPacketList>.size,packet,time,$0.count,$0.baseAddress!)}
            return MIDISend(port,destination,pointer)
        }
    }
    private func releaseAll(){
        MIDIFlushOutput(destination)
        for channel in 0..<16{_ = send(time:0,status:Int32(0xb0|channel),a:64,b:0);_ = send(time:0,status:Int32(0xb0|channel),a:123,b:0);_ = send(time:0,status:Int32(0xb0|channel),a:120,b:0)}
    }
    private func drain(){
        if lg_midi_output_error(hub.pointer) != 0,!failed {
            failed=true;if destination != 0{releaseAll()};_ = lg_midi_output_configure(hub.pointer,nil,0,0);lg_midi_output_failed(hub.pointer,-1000)
        }
        let count=buffer.withUnsafeMutableBufferPointer{lg_midi_output_pop(hub.pointer,$0.baseAddress,Int32($0.count))}
        guard destination != 0,!failed else{return}
        for event in buffer.prefix(Int(count)) where event.epoch==epoch {
            // A control-thread None/retry invalidates this batch immediately,
            // before its asynchronous endpoint cleanup reaches this queue.
            guard lg_midi_output_active_epoch(hub.pointer)==epoch else{return}
            if event.status==0{releaseAll();continue}
            let status=send(time:event.hostTime,status:event.status,a:event.a,b:event.b)
            if status != noErr{lg_midi_output_failed(hub.pointer,status);return};lg_midi_output_sent(hub.pointer,1)
        }
    }
}
