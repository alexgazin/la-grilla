import SwiftUI
import MusicDomain

enum TrackSoundNames {
    static func title(_ version:Int,role:TrackRole)->String {
        guard let palette=SoundPalette(rawValue:version) else{return "Classic sound"}
        if palette == .legacy{return "Original sound"}
        switch (role,palette) {
        case (.harmony,.classic):return "Classic keys"
        case (.harmony,.warm):return "Warm keys"
        case (.harmony,.bright):return "Bright keys"
        case (.drums,.classic):return "Classic kit"
        case (.drums,.warm):return "Warm kit"
        case (.drums,.bright):return "Bright kit"
        case (.bass,.classic):return "Classic bass"
        case (.bass,.warm):return "Warm bass"
        case (.bass,.bright):return "Bright bass"
        case (.melody,.classic):return "Classic lead"
        case (.melody,.warm):return "Warm lead"
        case (.melody,.bright):return "Bright lead"
        default:return "Classic sound"
        }
    }
    static func detail(_ palette:SoundPalette)->String {
        switch palette {
        case .legacy:return "Preserves the sound of this older project."
        case .classic:return "The original built-in tone."
        case .warm:return "Rounder body and softer high frequencies."
        case .bright:return "More presence and upper harmonics."
        }
    }
}

/// A visible entry point that can be shared by Mixer, Jam and note editors.
struct TrackSoundButton:View {
    @Bindable var session:Session
    let trackID:UUID
    var compact=false
    @State private var presented=false
    private var track:Track?{session.displayProject.tracks.first{$0.id==trackID}}
    private var locked:Bool{session.performance.contextActive || session.recording || session.armed}
    var body:some View {
        if let track {
            Button{presented=true}label:{
                HStack(spacing:compact ? 4:8){
                    Image(systemName:"waveform").font(compact ? .caption:.body)
                    VStack(alignment:.leading,spacing:2){
                        Text("Sound").font(compact ? .system(size:11,weight:.medium):.caption)
                        Text(LocalizedStringKey(TrackSoundNames.title(track.presetVersion,role:track.role)))
                            .font(compact ? .system(size:11,weight:.semibold):.subheadline.weight(.semibold))
                            .lineLimit(2).fixedSize(horizontal:false,vertical:true)
                    }
                    if !compact{Spacer(minLength:0);Image(systemName:"chevron.right").font(.caption)}
                }.frame(maxWidth:.infinity,minHeight:48,alignment:.leading)
                    .padding(.horizontal,compact ? 5:12)
                    .background(Color.track(track.role).opacity(0.12),in:RoundedRectangle(cornerRadius:10,style:.continuous))
            }.buttonStyle(StudioQuietButtonStyle()).foregroundStyle(Color.track(track.role))
                .disabled(locked)
                .accessibilityLabel(String(format:NSLocalizedString("Sound for %@",comment:"Track sound"),track.displayName))
                .accessibilityValue(LocalizedStringKey(TrackSoundNames.title(track.presetVersion,role:track.role)))
                .accessibilityIdentifier("sound.track.\(track.role.rawValue).\(trackID.uuidString)")
                .sheet(isPresented:$presented){TrackSoundPicker(session:session,trackID:trackID)}
        }
    }
}

struct TrackSoundPicker:View {
    @Bindable var session:Session
    let trackID:UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedVersion:Int
    @State private var sourceID:UUID
    @State private var sourceRevision:Int
    @State private var previewing=false
    @State private var previewAlongsideTrack=false
    @State private var error:String?

    init(session:Session,trackID:UUID){
        self.session=session;self.trackID=trackID
        _selectedVersion=State(initialValue:session.project.tracks.first{$0.id==trackID}?.presetVersion ?? 2)
        _sourceID=State(initialValue:session.project.id)
        _sourceRevision=State(initialValue:session.project.revision)
    }
    private var track:Track?{session.project.tracks.first{$0.id==trackID}}
    private var locked:Bool{session.performance.contextActive || session.recording || session.armed}
    private var contextMatches:Bool{session.project.id==sourceID && session.project.revision==sourceRevision && track != nil}
    private var canChange:Bool{contextMatches && !locked}
    private var sounding:Bool{previewing && session.harmonyPreview && session.audio.playing}
    private var choices:[SoundPalette]{track?.presetVersion==1 ? [.legacy]+SoundPalette.selectable:SoundPalette.selectable}

    var body:some View {
        NavigationStack {
            ScrollView {VStack(alignment:.leading,spacing:18){
                if let track {
                    VStack(alignment:.leading,spacing:6){
                        Text(track.displayName).font(.title2.weight(.semibold))
                        Text(LocalizedStringKey(track.role == .drums ? "Built-in synthesized kit · 16 pads":"Built-in instrument"))
                            .font(.caption).foregroundStyle(Color.muted)
                    }
                    ForEach(choices,id:\.rawValue){palette in paletteRow(palette,track:track)}
                    Text(LocalizedStringKey(previewAlongsideTrack || (!previewing && session.audio.playing) ? "Hear the sound with your track. Your notes stay unchanged.":"Preview plays a short example. Your notes stay unchanged."))
                        .font(.caption).foregroundStyle(Color.muted)
                    if previewAlongsideTrack || (!previewing && session.audio.playing){
                        Text("While playing, sound changes on the next bar.").font(.caption2).foregroundStyle(Color.muted)
                    }
                    Button{if sounding{stopPreview()}else{startPreview()}}label:{
                        Label(LocalizedStringKey(sounding ? "Stop preview":"Hear sound"),systemImage:sounding ? "stop.fill":"speaker.wave.2.fill")
                    }.buttonStyle(StudioActionStyle(color:Color.track(track.role),prominent:false))
                        .disabled(!canChange).accessibilityIdentifier("sound.preview")
                        .accessibilityValue(Text(verbatim:session.runtimeTraceEnabled ? session.runtimeTraceReport:""))
                    Text("Preview follows your track and master levels.")
                        .font(.caption2).foregroundStyle(Color.muted)
                }else{ContentUnavailableView("Track unavailable",systemImage:"waveform")}
                if !contextMatches{Text("The project changed. Close this picker and open it again.").font(.caption).foregroundStyle(Color.record)}
                if let error{Text(LocalizedStringKey(error)).font(.caption).foregroundStyle(Color.record).accessibilityIdentifier("sound.error")}
            }.padding(18)}.background(Color.ink)
                .safeAreaInset(edge:.bottom){
                    Button{apply()}label:{Text("Apply sound").frame(maxWidth:.infinity)}
                        .buttonStyle(StudioActionStyle())
                        .disabled(!canChange || selectedVersion==track?.presetVersion)
                        .padding(16).background(Color.ink).accessibilityIdentifier("sound.apply")
                }
                .navigationTitle("Sound").navigationBarTitleDisplayMode(.inline)
                .toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){stopPreview();dismiss()}}}
        }.presentationDetents([.large]).presentationDragIndicator(.visible).presentationBackground(Color.panel).tint(.mint)
            .onDisappear{stopPreview()}
            .onChange(of:session.project.id){_,_ in stopPreview()}
            .onChange(of:session.project.revision){_,_ in stopPreview()}
            .onChange(of:scenePhase){_,value in if value != .active{stopPreview()}}
    }

    private func paletteRow(_ palette:SoundPalette,track:Track)->some View {
        let selected=selectedVersion==palette.rawValue
        return Button{
            selectedVersion=palette.rawValue;error=nil
            if sounding{startPreview()}
        }label:{
            HStack(spacing:12){
                Image(systemName:selected ? "checkmark.circle.fill":"circle")
                    .font(.title3).foregroundStyle(selected ? Color.track(track.role):Color.muted)
                VStack(alignment:.leading,spacing:5){
                    Text(LocalizedStringKey(TrackSoundNames.title(palette.rawValue,role:track.role)))
                        .font(.headline).foregroundStyle(Color.studioText)
                    Text(LocalizedStringKey(TrackSoundNames.detail(palette)))
                        .font(.caption).foregroundStyle(Color.muted).multilineTextAlignment(.leading)
                }
                Spacer(minLength:0)
            }.frame(maxWidth:.infinity,minHeight:68,alignment:.leading).padding(12)
                .background(selected ? Color.track(track.role).opacity(0.13):Color.panel,in:RoundedRectangle(cornerRadius:14,style:.continuous))
                .overlay{RoundedRectangle(cornerRadius:14,style:.continuous).stroke(selected ? Color.track(track.role):Color.outline,lineWidth:selected ? 1.5:0.6)}
        }.buttonStyle(StudioQuietButtonStyle()).disabled(!canChange)
            .accessibilityAddTraits(selected ? [.isSelected]:[])
            .accessibilityIdentifier("sound.palette.\(palette.rawValue)")
    }

    private func startPreview(){
        guard canChange,let palette=SoundPalette(rawValue:selectedVersion) else{return}
        do{
            if !previewing{previewAlongsideTrack=session.audio.playing}
            if previewAlongsideTrack {
                var candidate=session.project
                guard let index=candidate.tracks.firstIndex(where:{$0.id==trackID})else{return}
                candidate.tracks[index].presetVersion=palette.rawValue
                session.previewAssistant(candidate,wholeSong:false,sectionID:session.section.id,rangeOverride:session.loopRange,loopOverride:session.loop)
            }else{
                let candidate=try TrackSoundPreview.project(from:session.project,trackID:trackID,palette:palette)
                session.previewHarmony(candidate,section:candidate.sections[0])
            }
            previewing=session.harmonyPreview
            error=session.audio.error
        }catch{self.error=error.localizedDescription}
    }
    private func stopPreview(){
        guard previewing else{return}
        previewing=false;previewAlongsideTrack=false;session.endHarmonyPreview()
    }
    private func apply(){
        guard canChange,SoundPalette(rawValue:selectedVersion) != nil,selectedVersion != track?.presetVersion else{return}
        stopPreview()
        let previous=session.project.revision
        session.edit{project in
            guard let index=project.tracks.firstIndex(where:{$0.id==trackID})else{throw MusicError.invalidProject}
            project.tracks[index].presetVersion=selectedVersion
        }
        if session.project.revision != previous{dismiss()}else{error=session.message}
    }
}
