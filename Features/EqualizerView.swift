import SwiftUI
import MusicDomain

enum EQDestination: Hashable, Identifiable {
    case track(UUID), master
    var id: Self { self }
}

struct EqualizerView: View {
    @Bindable var session: Session
    let destination: EQDestination
    @Environment(\.dismiss) private var dismiss
    @State private var selected = 0
    @State private var dragging = false
    /// U55 · With / without the EQ at matched loudness.
    enum Compare: Hashable { case processed, bypassed }
    @State private var compare = Compare.processed
    @State private var comparison: EffectBypass.Comparison?
    @State private var comparedRevision = -1
    @State private var matching = false
    private var track: Track? {
        guard case .track(let id)=destination else { return nil }
        return session.project.tracks.first { $0.id == id }
    }
    private var eq: StudioEQ {
        (destination == .master ? session.project.masterEQ : track?.equalizer) ?? StudioEQ()
    }
    /// Luz: the curve and band handles take the track's colour (mint on the master).
    private var tint: Color { track.map { Color.track($0) } ?? .mint
    }
    private var band: EQBand { eq.bands[selected] }
    private var title: String { track?.displayName ?? NSLocalizedString("Master",comment:"Mixer output") }
    private var activePreset: EQPreset? { EQPreset.library.first { $0.settings.bands == eq.bands } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    HStack {
                        Text(title).font(.title2.weight(.semibold))
                        Spacer()
                        Toggle("EQ on",isOn:Binding(get:{eq.enabled},set:{value in update { $0.enabled=value }}))
                            .fixedSize().tint(.mint)
                    }
                    presetMenu
                    response
                    Picker("Band",selection:$selected) {
                        ForEach(0..<4,id:\.self){ i in Text("\(i+1)").tag(i) }
                    }.pickerStyle(.segmented)
                    bandEditor
                    compareSection
                }
                .padding()
            }
            .background(Color.ink)
            .navigationTitle("Parametric EQ").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.confirmationAction){Button("Done"){dismiss()}} }
        }
        .tint(.mint)
        .onDisappear { session.mixerGesture=false; session.endHarmonyPreview() }
        .onChange(of:compare){ _,_ in if session.harmonyPreview { playComparison() } }
        .onChange(of:session.performance.contextActive){ _,active in if active { dismiss() } }
        .onChange(of:session.project.tracks.map(\.id)){ _,_ in
            if case .track = destination, track == nil { dismiss() }
        }
    }

    private var compareTarget: EffectBypass.Target { track.map { .trackEQ($0.id) } ?? .masterEQ }
    private var compareRange: Range<Int> { HoldPreview.range(session.project, from: session.section.start) }

    /// U55 · Hear the section with and without the EQ; "without" is turned up or down to the same
    /// loudness first, so the difference is the tone.
    private var compareSection: some View {
        VStack(alignment:.leading,spacing:8) {
            if matching { LoadingSkeleton(rows:2,caption:"Matching levels on this section…").accessibilityIdentifier("eq.matching") }
            AuditionBar(screen:"eq",source:$compare,sources:[(.processed,"With EQ"),(.bypassed,"Without EQ")],
                        playing:session.harmonyPreview,enabled:eq.enabled && !matching && !session.performance.contextActive,
                        caption:"Without EQ plays at the same loudness, so you hear the tone, not the level.",
                        play:playComparison,stop:{session.endHarmonyPreview()})
            if let comparison,comparedRevision == session.project.revision {
                Text(String(format:NSLocalizedString("Level match: %+.1f dB without the EQ",comment:"EQ comparison"),comparison.offsetDB))
                    .font(.caption.monospaced()).foregroundStyle(Color.muted).accessibilityIdentifier("eq.match")
            }
        }
    }

    private func playComparison() {
        let range = compareRange, sectionID = session.section.id
        if compare == .processed {
            session.previewAssistant(session.project,wholeSong:false,sectionID:sectionID,rangeOverride:range,loopOverride:true); return
        }
        if let comparison, comparedRevision == session.project.revision {
            session.previewAssistant(comparison.bypassed,wholeSong:false,sectionID:sectionID,rangeOverride:range,loopOverride:true); return
        }
        matching = true
        let project = session.project, target = compareTarget, samples = session.audio.samples
        Task { @MainActor in
            defer { matching = false }
            guard let result = try? await EffectBypass.matched(project,target:target,range:range,samples:samples),
                  session.project.revision == project.revision, session.project.id == project.id else { return }
            comparison = result; comparedRevision = project.revision
            if compare == .bypassed { session.previewAssistant(result.bypassed,wholeSong:false,sectionID:sectionID,rangeOverride:range,loopOverride:true) }
        }
    }

    private var presetMenu:some View {
        Menu {
            ForEach(EQPreset.library.map(\.family).reduce(into:[String]()){ list, item in
                if !list.contains(item) { list.append(item) }
            },id:\.self) { group in
                Menu(LocalizedStringKey(group)) {
                    ForEach(EQPreset.library.filter{$0.family==group}){ preset in
                        Button {
                            update { $0=preset.settings }
                        } label: {
                            if activePreset?.id==preset.id {
                                Label(LocalizedStringKey(preset.name),systemImage:"checkmark")
                            } else { Text(LocalizedStringKey(preset.name)) }
                        }
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName:"slider.horizontal.3")
                Text(LocalizedStringKey(activePreset?.name ?? "Custom EQ"))
                Spacer()
                Image(systemName:"chevron.up.chevron.down")
            }.padding(12).background(Color.panel,in:RoundedRectangle(cornerRadius:StudioMetrics.controlRadius,style:.continuous))
        }.accessibilityLabel("EQ presets").accessibilityValue(LocalizedStringKey(activePreset?.name ?? "Custom EQ"))
    }

    private func x(_ hz:Double)->Double { log10(hz/20)/3 }
    private func hz(_ x:Double)->Double { 20*pow(1000,min(1,max(0,x))) }
    private var response:some View {
        VStack(alignment:.leading,spacing:4) {
            Canvas { context,size in
                func point(_ normalized:Double,_ db:Double)->CGPoint {
                    let y:Double=(18-min(18,max(-18,db)))/36
                    return CGPoint(x:CGFloat(normalized)*size.width,y:CGFloat(y)*size.height)
                }
                var grid=Path()
                let gainGrid:[Double]=[-12,-6,0,6,12]
                let frequencyGrid:[Double]=[50,100,500,1000,5000,10000]
                for db in gainGrid {grid.move(to:point(0,db));grid.addLine(to:point(1,db))}
                for f in frequencyGrid {grid.move(to:point(x(f),-18));grid.addLine(to:point(x(f),18))}
                context.stroke(grid,with:.color(.outline),lineWidth:0.6)
                let snapshot=eq
                let response=snapshot.response(at:(0...160).map{hz(Double($0)/160)},rate:session.audio.sampleRate)
                var curve=Path()
                for (i,value) in response.enumerated() {
                    let p=point(Double(i)/160,value)
                    if i==0{curve.move(to:p)}else{curve.addLine(to:p)}
                }
                context.stroke(curve,with:.color(snapshot.enabled ? tint : .muted),lineWidth:2.5)
                for (i,b) in snapshot.bands.enumerated() {
                    let p=point(x(b.frequency),b.filter.hasGain ? b.gain:0)
                    let r:CGFloat=i==selected ? 6:3.5
                    context.fill(Path(ellipseIn:CGRect(x:p.x-r,y:p.y-r,width:2*r,height:2*r)),with:.color(b.enabled && snapshot.enabled ? tint:.muted))
                }
            }
            .frame(height:154).background(Color.panel,in:RoundedRectangle(cornerRadius:Luz.Radius.cell,style:.continuous))
            .overlay { GeometryReader { proxy in
                Color.clear.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance:0).onChanged{ value in
                        let size=proxy.size
                        guard size.width>0,size.height>0 else{return}
                        let width=Double(size.width), height=Double(size.height)
                        if !dragging {
                            dragging=true;session.mixerGesture=false
                            let start=value.startLocation
                            let distances = eq.bands.map { band in
                                let dx = x(band.frequency) * width - Double(start.x)
                                let level = band.filter.hasGain ? band.gain : 0
                                let dy = (18-level)/36 * height - Double(start.y)
                                return hypot(dx,dy)
                            }
                            selected = distances.indices.min { distances[$0] < distances[$1] } ?? selected
                        }
                        guard abs(value.translation.width)+abs(value.translation.height)>2 else{return}
                        let index=selected
                        let frequency=hz(Double(value.location.x)/width)
                        let gain:Double=min(18,max(-18,18-36*Double(value.location.y)/height))
                        update(continuous:true){ settings in
                            settings.bands[index].frequency=frequency
                            if settings.bands[index].filter.hasGain {
                                settings.bands[index].gain=gain
                            }
                        }
                    }.onEnded{ _ in dragging=false;session.mixerGesture=false })
            }}
            .accessibilityHidden(true)
            HStack {Text(verbatim:"20 Hz");Spacer();Text(verbatim:"632 Hz");Spacer();Text(verbatim:"20 kHz")}
                .font(.caption2.monospacedDigit()).foregroundStyle(Color.muted)
        }
    }

    private var bandEditor:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Picker("Filter type",selection:Binding(get:{band.filter},set:{ type in update { $0.bands[selected].filter=type } })){
                    ForEach(EQFilter.allCases,id:\.self){ type in Text(LocalizedStringKey(type.title)).tag(type) }
                }.pickerStyle(.menu)
                Spacer()
                Toggle("Band on",isOn:Binding(get:{band.enabled},set:{ value in update { $0.bands[selected].enabled=value } }))
                    .fixedSize()
            }
            control("Frequency",value:String(format:"%.0f Hz",band.frequency),binding:Binding(get:{x(band.frequency)},set:{ n in update(continuous:true){$0.bands[selected].frequency=hz(n)} }),range:0...1)
            if band.filter.hasGain {
                control("Gain",value:String(format:"%+.1f dB",band.gain),binding:Binding(get:{band.gain},set:{ v in update(continuous:true){$0.bands[selected].gain=v} }),range:-18...18)
                    // I52: the low and high bands of a track EQ can follow a MIDI knob.
                    .contextMenu{if case .track(let id)=destination,selected==0 || selected==3{MIDIAssignButton(session:session,target:selected==0 ? .eqLow:.eqHigh,trackID:id)}}
            }
            control("Q",value:String(format:"%.2f",band.q),binding:Binding(get:{log2(band.q)},set:{ v in update(continuous:true){$0.bands[selected].q=pow(2,v)} }),range:-2...3)
        }.padding(14).background(Color.panel,in:RoundedRectangle(cornerRadius:Luz.Radius.card,style:.continuous))
    }
    private func control(_ title:LocalizedStringKey,value:String,binding:Binding<Double>,range:ClosedRange<Double>)->some View {
        VStack(spacing:3) {
            HStack { Text(title);Spacer();Text(verbatim:value).monospacedDigit() }.font(.subheadline)
            Slider(value:binding,in:range,onEditingChanged:{ _ in session.mixerGesture=false })
                .accessibilityLabel(title).accessibilityValue(Text(verbatim:value))
        }
    }
    private func update(continuous:Bool=false,_ mutate:(inout StudioEQ)->Void) {
        guard !session.performance.contextActive else{return}
        var next=eq
        mutate(&next)
        guard next != eq else{return}
        let change:(inout Project)throws->Void = { project in
            switch destination {
            case .master: project.masterEQ=next
            case .track(let id):
                guard let index=project.tracks.firstIndex(where:{$0.id==id}) else{return}
                project.tracks[index].equalizer=next
            }
        }
        if continuous {session.mixerEdit(change)}else{session.mixerImmediate(change)}
    }
}
