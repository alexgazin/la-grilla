import SwiftUI
import CoreAudioKit
import MusicDomain

struct MIDIDevicesView:View {
    @Bindable var session:Session
    @State private var bluetooth=false
    @AppStorage("keyboard.mpe") private var mpe=false
    @State private var target:MIDIMapping.Target = .filter
    @State private var mappingTrack:UUID?
    private var settings:MIDISettings{session.project.midi ?? MIDISettings()}
    private var midi:MIDIController{session.midi}
    var body:some View {
        NavigationStack {Form {
            SwiftUI.Section {
                if let error=midi.error{Text(LocalizedStringKey(error)).foregroundStyle(Color.record).accessibilityIdentifier("midi.error")}
                Toggle("MIDI input",isOn:Binding(get:{settings.enabled},set:{value in edit{$0.enabled=value}})).accessibilityIdentifier("midi.enabled")
                // I54: an MPE controller bends and presses each note on its own channel.
                Toggle("MPE controller (bend and pressure per note)",isOn:Binding(get:{mpe},set:{on in mpe=on;session.audio.setMPE(on)})).accessibilityIdentifier("midi.mpe")
                Text("Play this project's instruments from a USB or Bluetooth MIDI controller. Mappings are saved with this project.").font(.caption).foregroundStyle(.secondary)
                if midi.isFixture{Text("Virtual MIDI QA source").font(.caption).foregroundStyle(Color.drums).accessibilityIdentifier("midi.fixture")}
            }
            SwiftUI.Section("Input devices") {
                if midi.sources.isEmpty{Text("No MIDI sources found. Connect a class-compliant USB device or pair Bluetooth MIDI.").foregroundStyle(.secondary)}
                ForEach(midi.sources){source in Toggle(isOn:Binding(get:{settings.inputIDs.contains(source.id)},set:{on in edit{value in if on{value.inputIDs.append(source.id)}else{value.inputIDs.removeAll{$0==source.id}}}})){VStack(alignment:.leading,spacing:4){Text(source.name);Text(LocalizedStringKey(midi.isConnected(source.id) ? "Connected":"Disconnected")).font(.caption).foregroundStyle(.secondary)}}.disabled(!settings.enabled)}
                Button("Bluetooth MIDI devices"){bluetooth=true}.frame(minHeight:44).accessibilityIdentifier("midi.bluetooth")
                Button("Refresh & reconnect"){reconnect()}.frame(minHeight:44).accessibilityIdentifier("midi.reconnect")
            }
            SwiftUI.Section("Play into") {
                Picker("Instrument",selection:Binding<UUID?>(get:{settings.trackID},set:{id in edit{$0.trackID=id}})){Text("The part you are editing").tag(UUID?.none);ForEach(session.project.tracks){track in Text(track.displayName).tag(Optional(track.id))}}
                Picker("Input channel",selection:Binding(get:{settings.channel ?? -1},set:{channel in edit{$0.channel=channel<0 ? nil:channel}})){Text("All channels").tag(-1);ForEach(0..<16,id:\.self){i in Text("Channel \(i+1)").tag(i)}}
                Text("Drums use General MIDI note numbers. NoteOn with velocity zero is NoteOff. CC64 controls sustain. Incoming notes are included when recording a performance take.").font(.caption).foregroundStyle(.secondary)
            }.disabled(!settings.enabled)
            SwiftUI.Section("MIDI output") {
                Picker("Destination",selection:Binding(get:{settings.outputID.map(Int64.init) ?? Int64.min},set:{id in edit{$0.outputID=id==Int64.min ? nil:Int32(id)}})){Text("None").tag(Int64.min);ForEach(midi.destinations){endpoint in Text(endpoint.name).tag(Int64(endpoint.id))}}
                if settings.outputID != nil{Toggle("Send MIDI clock",isOn:Binding(get:{settings.clockOut == true},set:{on in edit{$0.clockOut=on ? true:nil}})).accessibilityIdentifier("midi.clock-out")}
                Text("Project notes and live pads are sent to this destination. Incoming MIDI is not forwarded. Harmony uses channel 1, bass 2, drums 10, melodies 3–8.").font(.caption).foregroundStyle(.secondary)
                LabeledContent("Messages sent",value:String(midi.outputSent)).accessibilityIdentifier("midi.output-count")
                if midi.isFixture{HStack{Text("Virtual output received notes");Spacer();Text(String(midi.fixtureReceivedNotes)).accessibilityIdentifier("midi.fixture-received")}}
            }
            SwiftUI.Section("MIDI Learn") {
                Picker("Control",selection:$target){ForEach(MIDIMapping.Target.allCases,id:\.self){option in Text(title(option)).tag(option)}}
                if target == .trackGain || target == .trackPan{Picker("Track",selection:Binding(get:{mappingTrack ?? session.project.tracks[0].id},set:{mappingTrack=$0})){ForEach(session.project.tracks){track in Text(track.displayName).tag(track.id)}}}
                Button(LocalizedStringKey(midi.learning==nil ? "Learn next CC":"Cancel learn")){
                    if midi.learning != nil{midi.learning=nil}else{midi.learning=target;midi.learningTrack=target == .trackGain || target == .trackPan ? (mappingTrack ?? session.project.tracks[0].id):nil}
                }.frame(minHeight:44).accessibilityIdentifier("midi.learn").disabled(!settings.enabled || !midi.sources.contains(where:{midi.isConnected($0.id)}))
                if midi.learning != nil{Text("Move a controller knob. Sustain and channel-mode messages are reserved.").font(.caption).foregroundStyle(.secondary)}
                ForEach(settings.mappings){mapping in HStack{VStack(alignment:.leading){Text(title(mapping.target)).accessibilityIdentifier("midi.mapping.\(mapping.target.rawValue)");Text("Ch \(mapping.channel+1) · CC \(mapping.controller)").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("midi.mapping-detail.\(mapping.target.rawValue)")};Spacer();Button("Remove",role:.destructive){edit{$0.mappings.removeAll{$0.id==mapping.id}}}.font(.caption)}}
                if midi.isFixture{Button("Send virtual MIDI phrase"){midi.sendFixture()}.accessibilityIdentifier("midi.send-fixture")}
            }
            SwiftUI.Section("Activity") {
                Text(LocalizedStringKey(midi.lastMessage)).font(.system(.caption,design:.monospaced)).accessibilityIdentifier("midi.last")
                LabeledContent("Late input events",value:String(midi.late));LabeledContent("Dropped events",value:String(midi.dropped))
                Text("Late events play at the first available audio sample. Bluetooth audio latency is separate from Bluetooth MIDI.").font(.caption).foregroundStyle(.secondary)
                Button("Panic · release all notes",role:.destructive){session.panicMIDI()}.frame(minHeight:44).accessibilityIdentifier("midi.panic")
            }
        }.accessibilityIdentifier("midi.form").navigationTitle("MIDI devices").toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){midi.learning=nil;session.sheet=nil}.accessibilityIdentifier("midi.done").accessibilityValue(Text(verbatim:midi.fixtureRequested ? midi.fixtureReadiness:""))}}}
        .onAppear{midi.prepare();session.syncMIDI()}.onDisappear{midi.learning=nil}
        .sheet(isPresented:$bluetooth,onDismiss:{midi.endpointsChanged()}){NavigationStack{BluetoothMIDIPicker().navigationTitle("Bluetooth MIDI").toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){bluetooth=false}}}}}
    }
    private func reconnect(){
        midi.retry()
        if midi.fixtureRequested{session.prepareMIDIFixture()}else{session.syncMIDI()}
    }
    private func edit(_ change:@escaping(inout MIDISettings)->Void){session.edit{p in var value=p.midi ?? MIDISettings();change(&value);p.midi=value}}
    private func title(_ target:MIDIMapping.Target)->String{let key=switch target{case .masterGain:"Master gain";case .trackGain:"Track gain";case .trackPan:"Track pan";case .filter:"Master filter";case .delay:"Delay wet"};return NSLocalizedString(key,comment:"MIDI mapping target")}
}
private struct BluetoothMIDIPicker:UIViewControllerRepresentable {
    func makeUIViewController(context:Context)->CABTMIDICentralViewController{CABTMIDICentralViewController()}
    func updateUIViewController(_ controller:CABTMIDICentralViewController,context:Context){}
}
