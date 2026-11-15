import MediaPlayer

enum StudioRemoteAction:Sendable {case play,pause,toggle,stop}
private enum RemoteCallbacks {
    nonisolated static func handler(_ action:@escaping @MainActor @Sendable()->Void)->(MPRemoteCommandEvent)->MPRemoteCommandHandlerStatus {
        { @Sendable _ in Task{ @MainActor in action() };return .success }
    }
}

/// Installed only after an explicit playback action. No background keep-alive.
@MainActor final class NowPlayingController {
    private var tokens:[Any]=[]
    private var lastUpdate=Date.distantPast
    private var lastPlaying=false
    init(action:@escaping @MainActor @Sendable(StudioRemoteAction)->Void){
        let center=MPRemoteCommandCenter.shared()
        for (command,value) in [(center.playCommand,StudioRemoteAction.play),(center.pauseCommand,.pause),(center.togglePlayPauseCommand,.toggle),(center.stopCommand,.stop)] {
            command.isEnabled=true;tokens.append(command.addTarget(handler:RemoteCallbacks.handler{action(value)}))
        }
    }
    func update(title:String,seconds:Double,duration:Double,playing:Bool){
        guard playing != lastPlaying || Date().timeIntervalSince(lastUpdate)>=1 else{return}
        lastPlaying=playing;lastUpdate=Date()
        MPNowPlayingInfoCenter.default().nowPlayingInfo=[MPMediaItemPropertyTitle:title,MPMediaItemPropertyArtist:"La Grilla",MPMediaItemPropertyPlaybackDuration:duration,MPNowPlayingInfoPropertyElapsedPlaybackTime:seconds,MPNowPlayingInfoPropertyPlaybackRate:playing ? 1.0:0.0]
    }
    func clear(){MPNowPlayingInfoCenter.default().nowPlayingInfo=nil;lastUpdate = .distantPast;lastPlaying=false}
}
