import SwiftUI
import MusicDomain

struct HarmonyLabView:View {
    @Bindable var session:Session
    @AppStorage("studio.pitchSpelling") private var spellingValue=PitchSpelling.automatic.rawValue
    private var spelling:PitchSpelling{PitchSpelling(rawValue:spellingValue) ?? .automatic}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var style:HarmonyStyle = .gentle
    @State private var low=48
    @State private var high=84
    @State private var voicing:HarmonyVoicing = .compact
    @State private var proposal:HarmonyProposal?
    @State private var error:String?
    @State private var previewB=false
    @State private var showOptions=false
    @State private var showStyles=true
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:16){
                    Text("Give your chords a new color.").font(.system(.title2,weight:.semibold)).tracking(-0.6)
                    HStack{
                        Picker("Section",selection:Binding(get:{session.section.id},set:{id in invalidate();if let section=session.project.sections.first(where:{$0.id==id}){session.select(section)}})){ForEach(session.project.sections){section in Text(section.name).tag(section.id)}}.pickerStyle(.menu).frame(minHeight:44)
                        Spacer();CapsuleLabel(text:"ON DEVICE",color:.harmony)
                    }
                    if proposal==nil || showStyles {
                        LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:6){ForEach(HarmonyStyle.allCases,id:\.self){value in
                            Button{style=value;invalidate()}label:{HStack(spacing:6){Text(LocalizedStringKey(value.title)).font(.system(.subheadline,weight:.medium));Spacer(minLength:2);if style==value{Image(systemName:"checkmark").font(.caption.weight(.semibold))}}.padding(.horizontal,12).frame(maxWidth:.infinity,minHeight:44).foregroundStyle(style==value ? Color.ink:Color.studioText).background(style==value ? Color.harmony:Color.panel,in:RoundedRectangle(cornerRadius:StudioMetrics.controlRadius,style:.continuous))}.buttonStyle(StudioQuietButtonStyle())
                        }}
                        Text(description(style)).font(.caption).foregroundStyle(Color.muted)
                    }else{
                        Button{showStyles=true}label:{HStack{Text(LocalizedStringKey(style.title)).font(.subheadline.weight(.medium));Spacer();Image(systemName:"chevron.down").font(.caption)}}.buttonStyle(StudioQuietButtonStyle()).foregroundStyle(Color.harmony).frame(minHeight:44)
                    }
                    if let proposal{comparison(proposal)}else{
                        Text("Compare a proposal with your original. Nothing is saved until you apply it.").font(.caption).foregroundStyle(Color.muted)
                    }
                    if let error{Text(LocalizedStringKey(error)).foregroundStyle(Color.record).font(.callout)}
                    optionsPanel
                    // 55: the same chords, broken into an arpeggio written as editable notes.
                    Button{session.openArpeggiator(session.project.tracks.first{$0.role == .harmony}?.id)}label:{
                        Label("Arpeggiate these chords…",systemImage:"waveform.path.ecg").frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
                    }.buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier("harmony.arpeggiate")
                }.padding(18)
            }.accessibilityIdentifier("harmony.options-scroll").background(Color.ink).navigationTitle("Harmony lab").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge:.bottom){actionDock}
            .toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}}
        }.tint(.harmony).onAppear{if let index=ProcessInfo.processInfo.arguments.firstIndex(of:"--screen"),ProcessInfo.processInfo.arguments.count>index+1,ProcessInfo.processInfo.arguments[index+1]=="harmony-proposal"{generate()}}.onDisappear{session.endHarmonyPreview()}
    }
    private var optionsPanel:some View {
        VStack(alignment:.leading,spacing:10){
            Button{showOptions.toggle()}label:{
                HStack{
                    Text("Options")
                    Spacer(minLength:8)
                    Image(systemName:showOptions ? "chevron.up":"chevron.down").font(.caption.weight(.semibold)).accessibilityHidden(true)
                }.frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(Color.harmony)
                .accessibilityIdentifier("harmony.options")
                .accessibilityValue(LocalizedStringKey(showOptions ? "Expanded":"Collapsed"))
            if showOptions{optionsContent}
        }.font(.subheadline).padding(14).modifier(StudioSurface())
    }
    private var optionsContent:some View {
        VStack(alignment:.leading,spacing:10){
            optionRow("Voicing"){
                Picker("Voicing",selection:$voicing){ForEach(HarmonyVoicing.allCases,id:\.self){value in Text(LocalizedStringKey(value.rawValue)).tag(value)}}
                    .labelsHidden().pickerStyle(.menu).frame(minHeight:44).contentShape(Rectangle()).accessibilityIdentifier("harmony.voicing")
                    .onChange(of:voicing){_,_ in invalidate()}
            }
            Text("Compact voicings may omit the perfect fifth and intermediate extensions. Custom formulas keep every tone.").font(.caption).foregroundStyle(Color.muted)
            optionRow("Lowest note"){
                Picker("Lowest note",selection:$low){ForEach([36,48,60],id:\.self){pitch in Text(noteName(pitch,in:session.project)).tag(pitch)}}
                    .labelsHidden().pickerStyle(.menu).frame(minHeight:44).contentShape(Rectangle()).accessibilityIdentifier("harmony.lowest-note")
                    .onChange(of:low){_,_ in if high-low>60{high=low+60};invalidate()}
            }
            optionRow("Highest note"){
                Picker("Highest note",selection:$high){ForEach([72,84,96,108],id:\.self){pitch in Text(noteName(pitch,in:session.project)).tag(pitch)}}
                    .labelsHidden().pickerStyle(.menu).frame(minHeight:44).contentShape(Rectangle()).accessibilityIdentifier("harmony.highest-note")
                    .onChange(of:high){_,_ in if high-low>60{low=high-60};invalidate()}
            }
        }
    }
    @ViewBuilder private func optionRow<Content:View>(_ title:LocalizedStringKey,@ViewBuilder content:()->Content)->some View {
        if sizeClass == .compact || dynamicType.isAccessibilitySize {
            VStack(alignment:.leading,spacing:4){Text(title);content().frame(maxWidth:.infinity,alignment:.leading)}
        }else{
            HStack{Text(title);Spacer(minLength:8);content()}.frame(minHeight:44)
        }
    }
    @ViewBuilder private var actionDock:some View {
        VStack(spacing:8){
            if let proposal {
                HStack(spacing:8){
                    Button{previewB=false;session.previewHarmony(session.project,section:session.section)}label:{Label("A · Original",systemImage:"speaker.wave.2")}.buttonStyle(StudioActionStyle(color:.harmony,prominent:session.harmonyPreview && !previewB)).accessibilityIdentifier("harmony.a")
                    Button{previewB=true;session.previewHarmony(proposal.candidate,section:session.section)}label:{Label("B · Proposal",systemImage:"speaker.wave.2.fill")}.buttonStyle(StudioActionStyle(color:.harmony,prominent:session.harmonyPreview && previewB)).accessibilityIdentifier("harmony.b")
                    if session.harmonyPreview{IconButton(symbol:"stop.fill",label:"Stop preview",color:.harmony){session.endHarmonyPreview()}}
                }
                Text("Harmony + root bass · one Undo").font(.caption2).foregroundStyle(Color.muted)
                Button{apply(proposal)}label:{Text(String(format:NSLocalizedString("Apply to %@",comment:"Apply harmony to section"),session.section.name))}.buttonStyle(StudioActionStyle()).accessibilityIdentifier("harmony.apply")
            }else{
                Button{generate()}label:{Label("Generate proposal",systemImage:"sparkles")}.buttonStyle(StudioActionStyle()).accessibilityIdentifier("harmony.generate")
            }
        }.padding(.horizontal,18).padding(.top,10).padding(.bottom,8).background(Color.ink).overlay(alignment:.top){Rectangle().fill(Color.outline.opacity(0.6)).frame(height:0.5)}
    }
    func description(_ style:HarmonyStyle)->LocalizedStringKey {
        switch style{case .voiceLeading:"Keep the harmony; reduce movement between voices.";case .gentle:"Add warm sevenths with a comfortable register.";case .expressive:"Explore ninths and thirteenths with closer voices.";case .reharmonize:"Try borrowed minor IV and tritone dominant substitutions."}
    }
    private func noteName(_ pitch:Int,in project:Project)->String{MusicalNotation.noteName(pitch,keyRoot:project.keyRoot,minor:project.minor,spelling:spelling)}
    private func chordName(_ chord:Chord,in project:Project)->String{MusicalNotation.chordSymbol(chord,keyRoot:project.keyRoot,minor:project.minor,spelling:spelling)}
    func comparison(_ proposal:HarmonyProposal)->some View {
        VStack(alignment:.leading,spacing:8){
            HStack{SmallHeading(text:"ORIGINAL → PROPOSAL");Spacer();Button{generate()}label:{Image(systemName:"arrow.clockwise").frame(width:44,height:44)}.accessibilityLabel("Generate proposal").accessibilityIdentifier("harmony.generate")}
            ForEach(proposal.changes){change in
                HStack(spacing:12){
                    Text("\(change.tick/barTicks+1):\(change.tick%barTicks/ppq+1)").font(.system(.caption2,design:.monospaced)).foregroundStyle(Color.muted).frame(minWidth:24)
                    Text(chordName(change.before,in:proposal.candidate)).font(.system(.title3,weight:.semibold)).lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth:.infinity,alignment:.leading)
                    Image(systemName:"arrow.right").font(.caption).foregroundStyle(Color.muted)
                    VStack(alignment:.leading,spacing:4){Text(chordName(change.after,in:proposal.candidate)).font(.system(.title3,weight:.semibold)).foregroundStyle(Color.harmony).lineLimit(1).minimumScaleFactor(0.6);Text(MusicalNotation.chordNoteNames(change.after,keyRoot:proposal.candidate.keyRoot,minor:proposal.candidate.minor,spelling:spelling).joined(separator:" · ")).font(.system(.caption2, design: .monospaced)).foregroundStyle(Color.muted).lineLimit(2)}.frame(maxWidth:.infinity,alignment:.leading)
                    if change.chromatic{Image(systemName:"circle.lefthalf.filled").accessibilityLabel("Contains chromatic notes").foregroundStyle(Color.harmony)}
                }.padding(12).modifier(StudioSurface())
            }
            DisclosureGroup("Change details"){
                Text("Harmony and root bass in this section are affected. Melody and drums stay as written. Chromatic tones are marked. This is a deterministic local suggestion.").font(.caption).foregroundStyle(Color.muted).padding(.vertical,8)
                Text("One Undo restores your original harmony.").font(.caption).foregroundStyle(Color.muted)
            }.font(.caption).padding(.top,8)
        }
    }
    func invalidate(){session.endHarmonyPreview();proposal=nil;error=nil}
    func generate(){session.endHarmonyPreview();do{proposal=try HarmonyLab.propose(session.project,sectionID:session.section.id,options:HarmonyOptions(style:style,low:low,high:high,voicing:voicing));showOptions=false;showStyles=false;error=nil}catch{self.error=error.localizedDescription;proposal=nil}}
    func apply(_ proposal:HarmonyProposal){
        guard session.project.id==proposal.projectID,session.project.revision==proposal.revision else{error=HarmonyError.stale.localizedDescription;return}
        session.endHarmonyPreview();let revision=session.project.revision
        session.edit{try proposal.apply(to:&$0)}
        if session.project.revision>revision{dismiss()}
    }
}
