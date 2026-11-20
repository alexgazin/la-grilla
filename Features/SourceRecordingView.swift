import SwiftUI
import AVFoundation
import MusicDomain

struct SourceRecordingView:View {
    let session:Session;let record:AudioAssetRecord
    @Environment(\.dismiss) private var dismiss
    @State private var player:AVAudioPlayer?
    @State private var playing=false
    @State private var error:String?
    var body:some View {
        NavigationStack{VStack(spacing:24){Image(systemName:"waveform").font(.system(size:60)).foregroundStyle(Color.record);Text("Original voice").font(.title2);Text(String(format:"%.1f s · %.0f Hz · mono",record.duration,record.sampleRate)).font(.caption.monospaced()).foregroundStyle(Color.muted)
            if let tempo=record.tempoBPM{Text("Recorded at \(Int(tempo)) BPM").font(.caption).foregroundStyle(Color.muted)}
            if let error{Text(LocalizedStringKey(error)).foregroundStyle(Color.record)}
            Button{if let player{session.finishTake();session.audio.stop();if player.isPlaying{player.stop()}else{player.currentTime=0;player.play()};playing=player.isPlaying}}label:{Label(LocalizedStringKey(playing ? "Stop":"Play original"),systemImage:playing ? "stop.fill":"play.fill").frame(maxWidth:.infinity,minHeight:52).background(Color.record,in:RoundedRectangle(cornerRadius:StudioMetrics.controlRadius,style:.continuous)).foregroundStyle(Color.ink)}.disabled(player==nil)
            Text("The saved source recording. Your edited MIDI notes are separate.").font(.caption).foregroundStyle(Color.muted)
        }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity).background(Color.ink).navigationTitle("Source recording").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){dismiss()}}}}
            .task{do{let url=try await session.store.assetURL(record,projectID:session.project.id);_ = session.ensureAudio();let value=try AVAudioPlayer(contentsOf:url);value.prepareToPlay();player=value}catch{self.error=error.localizedDescription}}
            .onReceive(Timer.publish(every:0.2,on:.main,in:.common).autoconnect()){_ in playing=player?.isPlaying ?? false}
            .onDisappear{player?.stop();player=nil}
    }
}
