import Foundation

/// The caller must hold a full-validation certificate for `baseline`.
/// Only History calls this path. Shared COW music buffers are compared by value;
/// IDs/revisions alone never establish that two projects contain the same music.
enum MixEditValidation {
    static func validateChange(from baseline:Project,to candidate:Project)throws {
        guard candidate.master.isFinite,(-61...6).contains(candidate.master),
              candidate.tracks.count==baseline.tracks.count else{throw MusicError.invalidProject}
        try candidate.masterEQ?.validate()
        try candidate.masterFX?.validate()
        var normalized=candidate
        normalized.master=baseline.master
        normalized.masterEQ=baseline.masterEQ
        normalized.masterFX=baseline.masterFX
        normalized.revision=baseline.revision
        normalized.modified=baseline.modified
        for index in candidate.tracks.indices {
            let track=candidate.tracks[index]
            try track.equalizer?.validate()
            normalized.tracks[index].equalizer=baseline.tracks[index].equalizer
            guard track.gain.isFinite,(-61...6).contains(track.gain),
                  track.pan.isFinite,(-1...1).contains(track.pan) else{throw MusicError.invalidProject}
            normalized.tracks[index].gain=baseline.tracks[index].gain
            normalized.tracks[index].pan=baseline.tracks[index].pan
            normalized.tracks[index].mute=baseline.tracks[index].mute
            normalized.tracks[index].solo=baseline.tracks[index].solo
        }
        guard normalized==baseline else{throw MusicError.invalidProject}
    }
}
