import Foundation

/// Bounded persisted note names. MIDI pitch class remains the source of sound;
/// this stores the chosen letter/accidental, not the user's whitespace or casing.
enum ChordWriting {
    static func canonical(_ text:String)->String? {
        guard text.utf8.count<=9,let first=text.first else{return nil}
        let letter=String(first).uppercased()
        guard ["A","B","C","D","E","F","G"].contains(letter) else{return nil}
        let tail=String(text.dropFirst()).replacingOccurrences(of:"#",with:"♯").replacingOccurrences(of:"b",with:"♭")
        guard tail.count<=2,tail.isEmpty || tail.allSatisfy({$0=="♯"}) || tail.allSatisfy({$0=="♭"}) else{return nil}
        return letter+tail
    }
    static func pitchClass(_ text:String)->Int? {
        guard let name=canonical(text),let first=name.first,let natural=["C":0,"D":2,"E":4,"F":5,"G":7,"A":9,"B":11][String(first)] else{return nil}
        let tail=name.dropFirst(),offset=tail.filter{$0=="♯"}.count-tail.filter{$0=="♭"}.count
        return (natural+offset+12)%12
    }
    static func valid(_ spelling:String?,for pitch:Int)->Bool {
        guard let spelling else{return true}
        return canonical(spelling)==spelling && pitchClass(spelling)==pitch
    }
    static func name(_ spelling:String?,for pitch:Int)->String? {
        guard let spelling,valid(spelling,for:pitch)else{return nil}
        return spelling
    }
}
