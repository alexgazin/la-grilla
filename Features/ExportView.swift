import SwiftUI
import MusicDomain
import UIKit
struct ExportView:View {
    @Bindable var session:Session
    @State private var format:Session.ExportFormat = .midi
    @State private var scope=0
    @State private var sampleRate=48000
    @State private var bits=24
    @State private var tail=2.0
    @State private var firstBar=1
    @State private var lastBar=4
    @State private var tracks:Set<UUID>=[]
    private var take:PerformanceTake?{session.exportTake}
    private var project:Project{take?.source ?? session.project}
    private var formats:[Session.ExportFormat]{take==nil ? Session.ExportFormat.allCases:[.wav,.midi]}
    private var range:Range<Int>{scope==1 ? session.section.start..<session.section.start+session.section.length : scope==2 ? (firstBar-1)*barTicks..<lastBar*barTicks : 0..<session.project.length}
    var body:some View {
        NavigationStack {
            ScrollView {VStack(alignment:.leading,spacing:18){
                Text(LocalizedStringKey(take==nil ? "Take your idea further.":"Export your performance.")).font(.system(.title2,weight:.semibold)).tracking(-0.6)
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10){ForEach(formats){option in
                    Button{format=option}label:{Text(LocalizedStringKey(option.title)).font(.system(.subheadline,weight:.semibold)).frame(maxWidth:.infinity,minHeight:48).foregroundStyle(format==option ? Color.ink:Color.studioText).background(format==option ? Color.mint:Color.panel,in:RoundedRectangle(cornerRadius:14))}.buttonStyle(.plain).accessibilityIdentifier("format."+option.rawValue)
                }}.disabled(session.exportInProgress)
                if format != .project && take==nil {
                    StudioSegments(title:"Range",selection:$scope,options:[(0,"Entire song"),(1,"Selected section"),(2,"Bars")]).disabled(session.exportInProgress)
                    if scope==2 {VStack{Stepper("From bar \(firstBar)",value:$firstBar,in:1...lastBar);Stepper("Through bar \(lastBar)",value:$lastBar,in:firstBar...max(1,session.project.length/barTicks))}.font(.system(.subheadline)).disabled(session.exportInProgress)}
                }
                if format == .wav || format == .stems {audioSettings}
                if format == .stems {VStack(alignment:.leading,spacing:10){SmallHeading(text:"TRACKS");ForEach(project.tracks){t in Toggle(t.displayName,isOn:Binding(get:{tracks.contains(t.id)},set:{on in if on{tracks.insert(t.id)}else{tracks.remove(t.id)}})).tint(.mint)}}.disabled(session.exportInProgress)}
                if let error=session.exportError {Text(LocalizedStringKey(error)).font(.system(.caption)).foregroundStyle(Color.record).accessibilityIdentifier("export.error")}
                if format == .stems && tracks.isEmpty {Text("Select at least one track.").font(.caption).foregroundStyle(Color.muted)}
                Text(description).font(.system(.caption)).foregroundStyle(Color.muted).lineSpacing(4)
                HStack{Text("\(project.tracks.count) tracks");Spacer();Text("\(Int(project.bpm)) BPM · 4/4")}.font(.system(.caption,design:.monospaced)).foregroundStyle(Color.muted)
                if session.exportInProgress {VStack(alignment:.leading,spacing:8){ProgressView(value:session.exportProgress).tint(.mint);Text("\(Int(session.exportProgress*100))%").font(.system(.caption,design:.monospaced))}.accessibilityIdentifier("export.progress")}
                Button{session.export(format:format,settings:WAVSettings(sampleRate:sampleRate,bitDepth:bits,tailSeconds:tail),range:range,tracks:tracks,performance:take)}label:{HStack{if session.exportInProgress{ProgressView()};Text(LocalizedStringKey(session.exportInProgress ? "Exporting…":format == .midi ? "Export MIDI":"Export"));Image(systemName:"arrow.up.right")}}.buttonStyle(StudioActionStyle()).accessibilityIdentifier("export.confirm").disabled(session.exportInProgress || (format == .stems && tracks.isEmpty))
            }.padding(18)}.background(Color.ink)
            .navigationTitle("Export").navigationBarTitleDisplayMode(.inline)
            .toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){session.cancelExport();session.sheet=nil}}}
        }.presentationDetents([.large])
        .onAppear{if take != nil{tail=0};if let preset=session.exportPreset,let selected=Session.ExportFormat(rawValue:preset){format=selected;session.exportPreset=nil};lastBar=session.project.length/barTicks;tracks=Set(project.tracks.map(\.id))}
        .onDisappear{if session.exportInProgress{session.cancelExport()}}
    }
    private var audioSettings:some View {VStack(alignment:.leading,spacing:14){
        HStack{Text("Sample rate");Spacer();Picker("Sample rate",selection:$sampleRate){Text("44.1 kHz").tag(44100);Text("48 kHz").tag(48000)}.pickerStyle(.menu)}
        HStack{Text("Bit depth");Spacer();Picker("Bit depth",selection:$bits){Text("16 bit").tag(16);Text("24 bit").tag(24)}.pickerStyle(.menu)}
        HStack{Text("Tail");Spacer();Picker("Tail",selection:$tail){Text("0 s").tag(0.0);Text("1 s").tag(1.0);Text("2 s").tag(2.0);Text("5 s").tag(5.0);Text("10 s").tag(10.0)}.pickerStyle(.menu)}
    }.font(.system(.subheadline)).padding(14).modifier(StudioSurface()).disabled(session.exportInProgress)}
    private var description:LocalizedStringKey {
        if take != nil{return format == .midi ? "A finite MIDI sequence with section order, repeated notes, volume, pan and FX controllers. MIDI instruments and effects depend on your music software.":"The recorded section order and automation, rendered with the same instruments and effects as replay. A tail is optional."}
        return switch format {
        case .midi:"For editing notes in your music software. Instrument sounds are not included in MIDI."
        case .wav:"A stereo audio file using the same instruments as playback. Your live transport keeps running during export."
        case .stems:"Aligned stereo WAV files with a common start and tail. Track gain/pan and mute/solo are included; master gain is excluded."
        case .project:"A portable copy of the entire project, including notes, source recordings, sections and mixer settings. Import creates a separate project."
        }
    }
}
struct ShareView:UIViewControllerRepresentable {
    let url:URL
    func makeUIViewController(context:Context)->UIActivityViewController{UIActivityViewController(activityItems:[url],applicationActivities:nil)}
    func updateUIViewController(_ controller:UIActivityViewController,context:Context){}
}
