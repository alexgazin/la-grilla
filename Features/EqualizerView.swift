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
    private var track: Track? {
        guard case .track(let id)=destination else { return nil }
        return session.project.tracks.first { $0.id == id }
    }
    private var eq: StudioEQ {
        (destination == .master ? session.project.masterEQ : track?.equalizer) ?? StudioEQ()
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
                }
                .padding()
            }
            .background(Color.ink)
            .navigationTitle("Parametric EQ").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.confirmationAction){Button("Done"){dismiss()}} }
        }
        .tint(.mint)
        .onDisappear { session.mixerGesture=false }
        .onChange(of:session.performance.contextActive){ _,active in if active { dismiss() } }
        .onChange(of:session.project.tracks.map(\.id)){ _,_ in
            if case .track = destination, track == nil { dismiss() }
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
            }.padding(12).background(Color.panel,in:RoundedRectangle(cornerRadius:12))
        }.accessibilityLabel("EQ presets").accessibilityValue(LocalizedStringKey(activePreset?.name ?? "Custom EQ"))
    }

    private func x(_ hz:Double)->Double { log10(hz/20)/3 }
    private func hz(_ x:Double)->Double { 20*pow(1000,min(1,max(0,x))) }
    private var response:some View {
        VStack(alignment:.leading,spacing:4) {
            Canvas { context,size in
                func point(_ normalized:Double,_ db:Double)->CGPoint {
                    CGPoint(x:normalized*size.width,y:(18-min(18,max(-18,db)))/36*size.height)
                }
                var grid=Path()
                for db in [-12.0,-6,0,6,12] {grid.move(to:point(0,db));grid.addLine(to:point(1,db))}
                for f in [50.0,100,500,1000,5000,10000] {grid.move(to:point(x(f),-18));grid.addLine(to:point(x(f),18))}
                context.stroke(grid,with:.color(.outline),lineWidth:0.6)
                let snapshot=eq
                let response=snapshot.response(at:(0...160).map{hz(Double($0)/160)},rate:session.audio.sampleRate)
                var curve=Path()
                for (i,value) in response.enumerated() {
                    let p=point(Double(i)/160,value)
                    if i==0{curve.move(to:p)}else{curve.addLine(to:p)}
                }
                context.stroke(curve,with:.color(snapshot.enabled ? .mint : .muted),lineWidth:2.5)
                for (i,b) in snapshot.bands.enumerated() {
                    let p=point(x(b.frequency),b.filter.hasGain ? b.gain:0)
                    let r:CGFloat=i==selected ? 6:3.5
                    context.fill(Path(ellipseIn:CGRect(x:p.x-r,y:p.y-r,width:2*r,height:2*r)),with:.color(b.enabled && snapshot.enabled ? .harmony:.muted))
                }
            }
            .frame(height:154).background(Color.panel,in:RoundedRectangle(cornerRadius:10))
            .overlay { GeometryReader { proxy in
                Color.clear.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance:0).onChanged{ value in
                        let size=proxy.size
                        guard size.width>0,size.height>0 else{return}
                        if !dragging {
                            dragging=true;session.mixerGesture=false
                            let start=value.startLocation
                            selected=eq.bands.indices.min { a,b in
                                func distance(_ index:Int)->Double {
                                    let v=eq.bands[index]
                                    return hypot(x(v.frequency)*size.width-start.x,(18-(v.filter.hasGain ? v.gain:0))/36*size.height-start.y)
                                }
                                return distance(a)<distance(b)
                            } ?? selected
                        }
                        guard abs(value.translation.width)+abs(value.translation.height)>2 else{return}
                        let index=selected
                        update(continuous:true){ settings in
                            settings.bands[index].frequency=hz(value.location.x/size.width)
                            if settings.bands[index].filter.hasGain {
                                settings.bands[index].gain=min(18,max(-18,18-36*value.location.y/size.height))
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
            }
            control("Q",value:String(format:"%.2f",band.q),binding:Binding(get:{log2(band.q)},set:{ v in update(continuous:true){$0.bands[selected].q=pow(2,v)} }),range:-2...3)
        }.padding(14).background(Color.panel,in:RoundedRectangle(cornerRadius:14))
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
