import Foundation

/// Versioned built-in synthesis. Versions 1 and 2 preserve their historical
/// rendering exactly; Warm and Bright are actual alternate renderer palettes.
public enum SoundPalette:Int,CaseIterable,Sendable {
    case legacy=1,classic=2,warm=3,bright=4
    public static let selectable:[SoundPalette]=[.classic,.warm,.bright]
}

public enum TrackSoundPreview {
    /// A disposable one-bar example, never a mutation of the source document.
    /// Track identities and roles remain stable for the real audio routing.
    public static func project(from source:Project,trackID:UUID,palette:SoundPalette)throws->Project {
        try source.validate()
        guard let selected=source.tracks.firstIndex(where:{$0.id==trackID}) else{throw MusicError.invalidProject}
        var preview=source
        preview.sections=[Section(name:source.sections[0].name,length:barTicks)]
        preview.sections[0].id=source.sections[0].id
        preview.patterns=[];preview.performanceTakes=nil;preview.audioAssets=nil
        preview.masterFX=nil
        // Audition never raises either mixer level above the user's setting.
        preview.master=min(-6,source.master)
        for index in preview.tracks.indices {
            preview.tracks[index].clips=[]
            preview.tracks[index].mute=index != selected
            preview.tracks[index].solo=false
        }
        preview.tracks[selected].gain=min(-6,source.tracks[selected].gain)
        preview.tracks[selected].presetVersion=palette.rawValue
        preview.tracks[selected].instrumentSample = nil
        var pattern=Pattern(length:barTicks)
        let role=preview.tracks[selected].role
        switch role {
        case .drums:
            for tick in [0,1920]{pattern.drums.append(DrumEvent(tick:tick,pad:0,velocity:96))}
            for tick in [960,2880]{pattern.drums.append(DrumEvent(tick:tick,pad:1,velocity:92))}
            for tick in stride(from:0,to:barTicks,by:480){pattern.drums.append(DrumEvent(tick:tick,pad:2,velocity:65))}
        case .harmony,.bass:
            pattern.chords=[ChordEvent(tick:0,duration:barTicks,chord:Chord(root:source.keyRoot,quality:source.minor ? .minor:.major))]
        case .melody:
            for (index,interval) in [0,source.minor ? 3:4,7].enumerated(){
                pattern.notes?.append(NoteEvent(tick:index*960,duration:720,pitch:60+source.keyRoot+interval,velocity:90))
            }
        }
        preview.patterns=[pattern]
        // Bass is compiled from harmony; mute the harmony bus, not its source.
        let sourceTrack=role == .bass ? 0:selected
        preview.tracks[sourceTrack].clips=[Clip(patternID:pattern.id,start:0,length:barTicks)]
        try preview.validate()
        return preview
    }
}
