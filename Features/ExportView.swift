import SwiftUI
import MusicDomain
import UIKit
struct ExportView: View {
    @Bindable var session: Session
    @State private var sectionOnly=false;@State private var exporting=false
    var body: some View {NavigationStack{VStack(alignment:.leading,spacing:24){
        Image(systemName:"arrow.up.doc").font(.system(size:34,weight:.light)).foregroundStyle(Color.mint).padding(.top,20)
        Text("Take your idea further.").font(.system(size:25,weight:.medium))
        HStack{Text("Standard MIDI").fontWeight(.medium);Spacer();CapsuleLabel(text:".MID",color:.mint)}.padding(16).background(Color.raised,in:RoundedRectangle(cornerRadius:10))
        Picker("Range",selection:$sectionOnly){Text("Entire song").tag(false);Text("Selected section").tag(true)}.pickerStyle(.segmented)
        HStack{Text("\(session.project.tracks.count) tracks");Spacer();Text("\(Int(session.project.bpm)) BPM · 4/4")}.font(.system(size:12,design:.monospaced)).foregroundStyle(Color.muted)
        Text("For editing notes in your music software. Instrument sounds are not included in MIDI.").font(.system(size:13)).foregroundStyle(Color.muted).lineSpacing(5)
        Spacer()
        Button{exporting=true;Task{await session.export(sectionOnly:sectionOnly);exporting=false}}label:{HStack{if exporting{ProgressView()};Text(exporting ? "Exporting…":"Export MIDI");Image(systemName:"arrow.up.right")}.font(.system(size:16,weight:.semibold)).foregroundStyle(Color.ink).frame(maxWidth:.infinity,minHeight:52).background(Color.mint,in:RoundedRectangle(cornerRadius:12))}.accessibilityIdentifier("export.confirm").disabled(exporting)
    }.padding(24).background(Color.panel).navigationTitle("Export").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){session.sheet=nil}}}}.presentationDetents([.large])}
}
struct ShareView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context:Context)->UIActivityViewController{UIActivityViewController(activityItems:[url],applicationActivities:nil)}
    func updateUIViewController(_ controller:UIActivityViewController,context:Context){}
}
