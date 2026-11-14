import SwiftUI
import MusicDomain

struct HarmonyLabView:View {
    @Bindable var session:Session
    @Environment(\.dismiss) private var dismiss
    @State private var style:HarmonyStyle = .gentle
    @State private var low=48
    @State private var high=84
    @State private var proposal:HarmonyProposal?
    @State private var error:String?
    @State private var previewB=false
    @State private var showOptions=true
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20){
                    HStack{Image(systemName:"wand.and.stars").font(.system(size:32)).foregroundStyle(Color.harmony);Spacer();CapsuleLabel(text:"ON DEVICE",color:.harmony)}
                    Text("Give your chords a new color.").font(.system(size:27,weight:.medium))
                    Text("Compare a proposal with your original. Nothing is saved until you apply it.").font(.subheadline).foregroundStyle(Color.muted)
                    Picker("Section",selection:Binding(get:{session.section.id},set:{id in session.endHarmonyPreview();proposal=nil;if let s=session.project.sections.first(where:{$0.id==id}){session.select(s)}})){ForEach(session.project.sections){s in Text(s.name).tag(s.id)}}.pickerStyle(.menu)
                    DisclosureGroup("Options",isExpanded:$showOptions){VStack(alignment:.leading,spacing:10){
                        SmallHeading(text:"STYLE")
                        ForEach(HarmonyStyle.allCases,id:\.self){s in Button{style=s;invalidate()}label:{HStack{VStack(alignment:.leading,spacing:4){Text(LocalizedStringKey(s.title)).fontWeight(.medium);Text(description(s)).font(.caption).foregroundStyle(Color.muted)};Spacer();Image(systemName:style==s ? "checkmark.circle.fill":"circle").foregroundStyle(style==s ? Color.harmony:Color.muted)}.padding(12).frame(maxWidth:.infinity,minHeight:56).background(style==s ? Color.harmony.opacity(0.1):Color.panel,in:RoundedRectangle(cornerRadius:10))}.buttonStyle(.plain)}}
                    HStack {
                        Picker("Lowest note",selection:$low){ForEach([36,48,60],id:\.self){pitch in Text(NoteEvent(tick:0,pitch:pitch).name).tag(pitch)}}
                        Spacer()
                        Picker("Highest note",selection:$high){ForEach([72,84,96],id:\.self){pitch in Text(NoteEvent(tick:0,pitch:pitch).name).tag(pitch)}}
                    }.onChange(of:low){_,_ in invalidate()}.onChange(of:high){_,_ in invalidate()}}
                    Button{generate()}label:{Label("Generate proposal",systemImage:"sparkles").frame(maxWidth:.infinity,minHeight:48).background(Color.harmony,in:RoundedRectangle(cornerRadius:12)).foregroundStyle(Color.ink).fontWeight(.semibold)}.accessibilityIdentifier("harmony.generate")
                    if let error{Text(error).foregroundStyle(Color.record).font(.callout)}
                    if let proposal{comparison(proposal)}
                }.padding(20)
            }.background(Color.ink).navigationTitle("Harmony lab").navigationBarTitleDisplayMode(.inline)
            .toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}}
        }.tint(.harmony).onAppear{if let i=ProcessInfo.processInfo.arguments.firstIndex(of:"--screen"),ProcessInfo.processInfo.arguments.count>i+1,ProcessInfo.processInfo.arguments[i+1]=="harmony-proposal"{generate()}}.onDisappear{session.endHarmonyPreview()}
    }
    func description(_ s:HarmonyStyle)->LocalizedStringKey {
        switch s{case .voiceLeading:"Keep the harmony; reduce movement between voices.";case .gentle:"Add warm sevenths with a comfortable register.";case .expressive:"Explore ninths and thirteenths with closer voices.";case .reharmonize:"Try borrowed minor IV and tritone dominant substitutions."}
    }
    func comparison(_ p:HarmonyProposal)->some View {
        VStack(alignment:.leading,spacing:16){
            SmallHeading(text:"ORIGINAL → PROPOSAL")
            ForEach(p.changes){change in
                VStack(alignment:.leading,spacing:8){
                    HStack{Text("\(change.tick/barTicks+1):\(change.tick%barTicks/ppq+1)").font(.caption.monospaced()).foregroundStyle(Color.muted);Text(change.before.symbol);Image(systemName:"arrow.right").foregroundStyle(Color.muted);Text(change.after.symbol).foregroundStyle(Color.harmony);Spacer();if change.chromatic{Image(systemName:"circle.lefthalf.filled").accessibilityLabel("Contains chromatic notes").foregroundStyle(Color.harmony)}}
                    Text(change.after.notes.map{NoteEvent(tick:0,pitch:$0).name}.joined(separator:" · ")).font(.caption.monospaced()).foregroundStyle(Color.muted)
                }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.panel,in:RoundedRectangle(cornerRadius:10))
            }
            Text("Harmony and root bass in this section are affected. Melody and drums stay as written. Chromatic tones are marked. This is a deterministic local suggestion.").font(.caption).foregroundStyle(Color.muted)
            HStack(spacing:10){
                Button{previewB=false;session.previewHarmony(session.project,section:session.section)}label:{Label("A · Original",systemImage:"speaker.wave.2").frame(maxWidth:.infinity,minHeight:48).background(session.harmonyPreview && !previewB ? Color.harmony.opacity(0.25):Color.raised,in:RoundedRectangle(cornerRadius:10))}.accessibilityIdentifier("harmony.a")
                Button{previewB=true;session.previewHarmony(p.candidate,section:session.section)}label:{Label("B · Proposal",systemImage:"speaker.wave.2.fill").frame(maxWidth:.infinity,minHeight:48).background(session.harmonyPreview && previewB ? Color.harmony.opacity(0.25):Color.raised,in:RoundedRectangle(cornerRadius:10))}.accessibilityIdentifier("harmony.b")
            }.font(.subheadline)
            if session.harmonyPreview{Button("Stop preview"){session.endHarmonyPreview()}.frame(minHeight:44)}
            Button{apply(p)}label:{Text("Apply proposal").fontWeight(.semibold).foregroundStyle(Color.ink).frame(maxWidth:.infinity,minHeight:48).background(Color.harmony,in:RoundedRectangle(cornerRadius:12))}.accessibilityIdentifier("harmony.apply")
            Text("One Undo restores your original harmony.").font(.caption).foregroundStyle(Color.muted)
        }
    }
    func invalidate(){session.endHarmonyPreview();proposal=nil;error=nil}
    func generate(){session.endHarmonyPreview();do{proposal=try HarmonyLab.propose(session.project,sectionID:session.section.id,options:HarmonyOptions(style:style,low:low,high:high));showOptions=false;error=nil}catch{self.error=error.localizedDescription;proposal=nil}}
    func apply(_ p:HarmonyProposal){
        guard session.project.id==p.projectID,session.project.revision==p.revision else{error=HarmonyError.stale.localizedDescription;return}
        session.endHarmonyPreview();let revision=session.project.revision
        session.edit{try p.apply(to:&$0)}
        if session.project.revision>revision{dismiss()}
    }
}
