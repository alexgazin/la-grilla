import Foundation
import Testing
@testable import MusicDomain

struct ChordToneNotationTests {
    @Test func chordLettersDistinguishMinorThirdsAlterationsAndCompoundExtensions()throws {
        let examples:[String:[String]]=[
            "Cm":["C4","E♭4","G4"],"C7b9":["C4","E4","G4","B♭4","D♭5"],
            "C7#9":["C4","E4","G4","B♭4","D♯5"],"C7b5":["C4","E4","G♭4","B♭4"],
            "C7#11":["C4","E4","G4","B♭4","F♯5"],"C7b13":["C4","E4","G4","B♭4","A♭5"],
            "Caug":["C4","E4","G♯4"],"Cdim7":["C4","E♭4","G♭4","B♭♭4"],
            "C{0,3,7,11,14}":["C4","E♭4","G4","B4","D5"],
            "C{0,4,6}":["C4","E4","G♭4"],"C{0,4,6,7}":["C4","E4","F♯4","G4"],
            "C{0,4,7,13,20}":["C4","E4","G4","D♭5","A♭5"],
            "C{0,4,8,20}":["C4","E4","G♯4","A♭5"],
            "C{0,4,6,18}":["C4","E4","G♭4","F♯5"]
        ]
        for (symbol,expected) in examples {
            #expect(MusicalNotation.chordNoteNames(try Chord.parse(symbol),keyRoot:0,minor:false)==expected)
        }
    }

    @Test func writtenRootsSlashBassAndDoubleAccidentalsHaveTheCorrectOctave()throws {
        let examples:[String:[String]]=[
            "Dbm/Ab":["A♭2","D♭3","F♭3","A♭3"],
            "B#":["B♯3","D♯♯4","F♯♯4"],"Cb":["C♭4","E♭4","G♭4"],
            "C/Fb":["F♭3","C4","E4","G4"]
        ]
        for (symbol,expected) in examples {
            #expect(MusicalNotation.chordNoteNames(try Chord.parse(symbol),keyRoot:0,minor:false)==expected)
        }
    }

    @Test func everyCatalogToneAtEveryRootKeepsItsActualMidiPitch()throws {
        for root in 0..<12 {for quality in Quality.allCases {
            let chord=Chord(root:root,quality:quality,rootSpelling:Chord.roots[root])
            let names=MusicalNotation.chordNoteNames(chord,keyRoot:root,minor:false)
            #expect(names.count==chord.notes.count)
            for (pitch,name) in zip(chord.notes,names) {
                #expect(try midiPitch(name)==pitch,"\(chord.symbol): \(name)")
            }
        }}
    }

    @Test func explicitDisplayPreferenceOverridesToneWritingWithoutChangingMusic()throws {
        let chord=try Chord.parse("Cm7b5"),original=chord
        #expect(MusicalNotation.chordNoteNames(chord,keyRoot:0,minor:false)==["C4","E♭4","G♭4","B♭4"])
        #expect(MusicalNotation.chordNoteNames(chord,keyRoot:0,minor:false,spelling:.sharps)==["C4","D♯4","F♯4","A♯4"])
        #expect(MusicalNotation.chordNoteNames(chord,keyRoot:0,minor:false,spelling:.flats)==["C4","E♭4","G♭4","B♭4"])
        #expect(chord==original)
    }

    private func midiPitch(_ name:String)throws->Int {
        enum Invalid:Error{case name}
        guard let first=name.first,let base=["C":0,"D":2,"E":4,"F":5,"G":7,"A":9,"B":11][String(first)]else{throw Invalid.name}
        var tail=String(name.dropFirst()),offset=0
        while let char=tail.first,char=="♯" || char=="♭"{offset += char=="♯" ? 1:-1;tail.removeFirst()}
        guard let octave=Int(tail)else{throw Invalid.name}
        return (octave+1)*12+base+offset
    }
}
