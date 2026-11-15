import SwiftUI
import MusicDomain

struct ClipEditorSelection: Identifiable {
    let trackID: UUID
    let clipID: UUID
    var id: UUID { clipID }
}

struct ArrangementClipFace: View {
    let notes: [CompiledNote]
    let track: Track
    let clip: Clip
    let width: CGFloat
    let height: CGFloat
    let resizing: Bool
    private var color: Color { Color.track(track.role) }
    var body: some View {
        VStack(alignment:.leading,spacing:5) {
            if width>=62 {
                HStack(spacing:5) {
                    Image(systemName:track.role == .drums ? "square.grid.2x2":"pianokeys").font(.system(size:11))
                    Text(track.displayName).font(.system(size:11,weight:.semibold)).lineLimit(1)
                }.foregroundStyle(color).padding(.trailing,10)
            }
            Canvas { context,size in
                let visible=notes.filter{$0.tick<clip.start+clip.length && $0.tick+$0.duration>clip.start}
                let pitches=visible.map(\.pitch),low=pitches.min() ?? 48,high=max(low+1,pitches.max() ?? 84)
                let stride=max(1,visible.count/192)
                for (index,note) in visible.enumerated() where index%stride==0 {
                    let begin=max(clip.start,note.tick),end=min(clip.start+clip.length,note.tick+note.duration)
                    let x=CGFloat(begin-clip.start)/CGFloat(clip.length)*size.width
                    let y=track.role == .drums ? CGFloat(max(0,note.pad)%4)/4*max(1,size.height-4):CGFloat(high-note.pitch)/CGFloat(high-low)*max(1,size.height-4)
                    let length=track.role == .drums ? max(2,size.width/96):max(2,CGFloat(end-begin)/CGFloat(clip.length)*size.width)
                    context.fill(Path(roundedRect:CGRect(x:x,y:y,width:length,height:3),cornerRadius:1),with:.color(color.opacity(0.75)))
                }
            }.accessibilityHidden(true)
            if width>=110,height>=85 {
                Text("\(clip.start/barTicks+1):\(clip.start%barTicks/240+1) → \((clip.start+clip.length)/barTicks+1):\((clip.start+clip.length)%barTicks/240+1)")
                    .font(.system(size:11,design:.monospaced)).foregroundStyle(Color.muted).lineLimit(1)
            }
        }.padding(width<62 ? 3:9).frame(width:width,height:height,alignment:.topLeading)
            .background(color.opacity(resizing ? 0.2:0.1),in:RoundedRectangle(cornerRadius:11,style:.continuous))
            .overlay{RoundedRectangle(cornerRadius:11,style:.continuous).stroke(resizing ? Color.mint:color.opacity(0.4),lineWidth:resizing ? 2:1)}
            .contentShape(Rectangle())
    }
}

struct ArrangementClipInspector: View {
    @Bindable var session: Session
    let selection: ClipEditorSelection
    let editContents: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var grid=barTicks
    private var track: Track? {session.project.tracks.first{$0.id==selection.trackID}}
    private var clip: Clip? {track?.clips.first{$0.id==selection.clipID}}
    private var pattern: Pattern? {guard let clip else{return nil};return session.project.patterns.first{$0.id==clip.patternID}}
    private func payload() -> ArrangementDragPayload {
        ArrangementDragPayload(project:session.project,trackID:selection.trackID,clipID:selection.clipID)
    }
    private func commit(_ operation:(ArrangementDragPayload,inout Project)throws->Void) {
        let token=payload()
        session.edit{try operation(token,&$0)}
    }
    var body: some View {
        NavigationStack {
            Form {
                if let clip,let track,let pattern {
                    SwiftUI.Section {
                        LabeledContent("Track",value:track.displayName)
                        Button("Edit clip contents"){editContents()}.frame(minHeight:44).accessibilityIdentifier("clip.edit")
                        if clip.offset != 0 || clip.length != pattern.length {
                            Text("Editing the source pattern updates every loop of this clip.").font(.caption).foregroundStyle(Color.muted)
                        }
                    }
                    SwiftUI.Section("Clip position") {
                        Picker("Snap",selection:$grid){Text("1 bar").tag(barTicks);Text("1 beat").tag(ppq);Text("1/16").tag(240)}
                        Stepper(value:Binding(get:{clip.start},set:{value in commit{try ClipEditing.move($0,to:selection.trackID,start:value,snap:grid,in:&$1)}}),in:0...max(0,64*barTicks-clip.length),step:grid){
                            LabeledContent("Start",value:"\(clip.start/barTicks+1):\(clip.start%barTicks/240+1)")
                        }.accessibilityIdentifier("clip.start").accessibilityValue("\(clip.start/barTicks+1):\(clip.start%barTicks/240+1)")
                        Stepper(value:Binding(get:{clip.length},set:{value in commit{try ClipEditing.resize($0,length:value,snap:grid,in:&$1)}}),in:grid...max(grid,64*barTicks-clip.start),step:grid){
                            LabeledContent("Length",value:String(format:NSLocalizedString("%.2f bars",comment:"Clip length"),Double(clip.length)/Double(barTicks)))
                        }.accessibilityIdentifier("clip.length").accessibilityValue(String(format:NSLocalizedString("%.2f bars",comment:"Clip length"),Double(clip.length)/Double(barTicks)))
                        Stepper(value:Binding(get:{clip.offset},set:{value in commit{try ClipEditing.setOffset($0,offset:value,snap:240,in:&$1)}}),in:0...max(0,pattern.length-240),step:240){
                            LabeledContent("Source offset",value:"\(clip.offset/barTicks+1):\(clip.offset%barTicks/240+1)")
                        }.accessibilityIdentifier("clip.offset")
                    }
                    SwiftUI.Section {
                        Button("Duplicate clip"){commit{try ClipEditing.copy($0,to:selection.trackID,start:clip.start+clip.length,snap:240,in:&$1)}}.frame(minHeight:44).accessibilityIdentifier("clip.duplicate")
                        Button("Delete clip",role:.destructive){commit{try ClipEditing.delete($0,in:&$1)};if self.clip==nil{dismiss()}}.frame(minHeight:44).accessibilityIdentifier("clip.delete")
                    }
                    SwiftUI.Section {
                        Text("Clips repeat their source pattern when extended. Musical content is never overwritten by a drop.").font(.caption).foregroundStyle(Color.muted)
                    }
                } else {Text("This clip or section no longer exists.")}
            }.tint(track.map{Color.track($0.role)} ?? .mint)
                .navigationTitle("Clip settings").navigationBarTitleDisplayMode(.inline)
                .toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){dismiss()}}}
        }.onAppear{if let clip,clip.start%barTicks != 0 || clip.length%barTicks != 0{grid=clip.start%ppq==0 && clip.length%ppq==0 ? ppq:240}}
    }
}
