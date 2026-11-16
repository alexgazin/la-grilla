import SwiftUI
import MusicDomain

struct TransposeEditor: View {
    @Bindable var session:Session
    @Environment(\.dismiss) private var dismiss
    @AppStorage("studio.pitchSpelling") private var spellingValue=PitchSpelling.automatic.rawValue
    @State private var semitones=2
    @State private var proposal:TranspositionProposal?
    @State private var error:String?
    private var spelling:PitchSpelling{PitchSpelling(rawValue:spellingValue) ?? .automatic}
    private var locked:Bool{session.recording || session.armed || session.performance.contextActive}
    private var stale:Bool{proposal.map{$0.projectID != session.project.id || $0.revision != session.project.revision} ?? false}
    var body:some View {
        Form {
            Section {
                Text("Move every pitched note by the same interval. Drums keep their pitches and timing.")
                    .font(.callout).foregroundStyle(.secondary)
                Stepper(value:$semitones,in:-24...24){
                    LabeledContent("Semitones",value:String(format:"%+d",semitones)).monospacedDigit()
                }.accessibilityIdentifier("transpose.semitones")
                .accessibilityValue(String(semitones))
                .onChange(of:semitones){_,_ in review()}
            }
            if let proposal {
                Section("Review transposition") {
                    LabeledContent("Notes",value:String(proposal.noteCount)).accessibilityIdentifier("transpose.note-count")
                    LabeledContent("Key",value:keyName(session.project)+" → "+keyName(proposal.candidate)).accessibilityIdentifier("transpose.key")
                    if let before=proposal.originalRange,let after=proposal.transposedRange {
                        Text(noteRange(before,project:session.project)+" → "+noteRange(after,project:proposal.candidate))
                            .font(.callout.monospaced()).accessibilityIdentifier("transpose.pitch-range")
                    }
                    ForEach(session.project.tracks.filter{proposal.trackIDs.contains($0.id)}){track in
                        Label(track.displayName,systemImage:"music.note")
                    }
                    Text("Applies to the arrangement and its key context as one Undo. This changes notes; changing Key alone only changes suggestions.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Label("Original voice recordings and saved performances stay unchanged.",systemImage:"waveform")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if stale {
                Section {
                    Text("The project changed. Review a new transposition before applying.").foregroundStyle(Color.record)
                    Button("Review again"){review()}.accessibilityIdentifier("transpose.review-again")
                }
            }
            if let error{Section{Text(LocalizedStringKey(error)).foregroundStyle(Color.record).accessibilityIdentifier("transpose.error")}}
            Section {
                Button("Apply transposition"){
                    guard let proposal,!stale,!locked else{return}
                    let revision=session.project.revision
                    session.edit{try proposal.apply(to:&$0)}
                    if session.project.revision>revision{dismiss()}
                }.accessibilityIdentifier("transpose.apply").disabled(proposal==nil || stale || locked)
            }
        }
        .navigationTitle("Transpose arrangement").navigationBarTitleDisplayMode(.inline)
        .toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}.accessibilityIdentifier("transpose.cancel")}}
        .onAppear{review()}
    }
    private func review(){
        do{proposal=try MusicalEditing.transpose(session.project,semitones:semitones);error=nil}
        catch{proposal=nil;self.error=error.localizedDescription}
    }
    private func keyName(_ project:Project)->String {
        MusicalNotation.pitchClassName(project.keyRoot,keyRoot:project.keyRoot,minor:project.minor,spelling:spelling)+" "+NSLocalizedString(project.minor ? "minor":"major",comment:"Key mode")
    }
    private func noteRange(_ range:ClosedRange<Int>,project:Project)->String {
        MusicalNotation.noteName(range.lowerBound,keyRoot:project.keyRoot,minor:project.minor,spelling:spelling)+"–"+MusicalNotation.noteName(range.upperBound,keyRoot:project.keyRoot,minor:project.minor,spelling:spelling)
    }
}
