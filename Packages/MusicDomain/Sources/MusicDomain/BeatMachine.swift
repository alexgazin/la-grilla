import Foundation

// MARK: - Presets

/// Beat machine · A ready beat: a factory kit, a one- or two-bar step pattern for the
/// pads and an optional 808 or bass line in the song's key. Everything is original and
/// generated on the device.
public struct BeatPreset: Identifiable, Equatable, Sendable {
    public enum Genre: String, CaseIterable, Sendable, Identifiable {
        case trap, drill, boomBap, westCoast, lofi, phonk, rnb, pop, house, techno, garage, dnb, bass, reggaeton, afro, jersey, funk, rock, synthwave, electro, chiptune, jazz, world
        public var id: String { rawValue }
        /// English name; the app localizes it.
        public var title: String {
            switch self {
            case .trap: "Trap"
            case .drill: "Drill"
            case .boomBap: "Boom bap"
            case .westCoast: "West Coast"
            case .lofi: "Lo-fi"
            case .phonk: "Phonk"
            case .rnb: "R&B"
            case .pop: "Pop"
            case .house: "House"
            case .techno: "Techno"
            case .garage: "UK Garage"
            case .dnb: "Drum & Bass"
            case .bass: "Bass music"
            case .reggaeton: "Reggaeton"
            case .afro: "Afrobeats"
            case .jersey: "Jersey club"
            case .funk: "Funk & Disco"
            case .rock: "Rock"
            case .synthwave: "Synthwave"
            case .electro: "Electro"
            case .chiptune: "8-bit"
            case .jazz: "Jazz & Bossa"
            case .world: "World"
            }
        }
        /// SF Symbol drawn on the genre's artwork.
        public var symbol: String {
            switch self {
            case .trap: "flame.fill"
            case .drill: "bolt.fill"
            case .boomBap: "record.circle"
            case .westCoast: "sun.max.fill"
            case .lofi: "cloud.rain.fill"
            case .phonk: "car.fill"
            case .rnb: "heart.fill"
            case .pop: "star.fill"
            case .house: "house.fill"
            case .techno: "cpu.fill"
            case .garage: "figure.dance"
            case .dnb: "hare.fill"
            case .bass: "waveform.path"
            case .reggaeton: "sun.horizon.fill"
            case .afro: "leaf.fill"
            case .jersey: "sparkles"
            case .funk: "music.note"
            case .rock: "guitars.fill"
            case .synthwave: "moon.stars.fill"
            case .electro: "antenna.radiowaves.left.and.right"
            case .chiptune: "gamecontroller.fill"
            case .jazz: "music.quarternote.3"
            case .world: "globe.americas.fill"
            }
        }
        /// Two hues (0…1) for the artwork gradient.
        public var hues: (Double, Double) {
            switch self {
            case .trap: (0.98, 0.08)
            case .drill: (0.62, 0.72)
            case .boomBap: (0.08, 0.12)
            case .westCoast: (0.11, 0.55)
            case .lofi: (0.72, 0.58)
            case .phonk: (0.83, 0.95)
            case .rnb: (0.92, 0.80)
            case .pop: (0.88, 0.14)
            case .house: (0.50, 0.62)
            case .techno: (0.66, 0.78)
            case .garage: (0.30, 0.45)
            case .dnb: (0.40, 0.55)
            case .bass: (0.76, 0.86)
            case .reggaeton: (0.06, 0.15)
            case .afro: (0.12, 0.33)
            case .jersey: (0.85, 0.55)
            case .funk: (0.13, 0.03)
            case .rock: (0.00, 0.08)
            case .synthwave: (0.84, 0.55)
            case .electro: (0.52, 0.80)
            case .chiptune: (0.33, 0.20)
            case .jazz: (0.10, 0.60)
            case .world: (0.07, 0.42)
            }
        }
    }

    public struct Lane: Equatable, Sendable {
        public let pad: Int
        public let steps: String
    }

    public let id: String
    /// English name; the app localizes it.
    public let title: String
    public let genre: Genre
    public let bpm: Int
    /// 0.5 = straight; up to 0.66 delays every second sixteenth.
    public let swing: Double
    public let kit: FactoryDrumKit
    public let bass: FactorySynth?
    /// The mode the bass line was written in; it is adapted to the song's mode.
    public let minor: Bool
    public let lanes: [Lane]
    /// "step:semitones:length" tokens in sixteenths, semitones from the key's root.
    public let bassLine: String

    public var steps: Int { lanes.first.map { Self.clean($0.steps).count } ?? 16 }

    static func clean(_ text: String) -> String { text.replacingOccurrences(of: "|", with: "") }

    init(_ id: String, _ title: String, _ genre: Genre, bpm: Int, swing: Double = 0.5, kit: FactoryDrumKit,
         bass: FactorySynth? = .sub808, minor: Bool = true, _ lanes: [(Int, String)], bassLine: String = "") {
        self.id = id; self.title = title; self.genre = genre; self.bpm = bpm; self.swing = swing; self.kit = kit
        self.bass = bass; self.minor = minor; self.lanes = lanes.map { Lane(pad: $0.0, steps: $0.1) }; self.bassLine = bassLine
    }

    public static func preset(_ id: String) -> BeatPreset? { library.first { $0.id == id } }
    public static func presets(_ genre: Genre) -> [BeatPreset] { library.filter { $0.genre == genre } }
}

// Pads: 0 kick, 1 snare, 2 closed hat, 3 open hat, 4 clap, 5 rim, 6–8 toms, 9 crash, 10 ride,
// 11 tambourine, 12 cowbell, 13 clave, 14 shaker, 15 perc.
// Steps: X accent, x hit, o ghost, 2–4 a roll of that many hits, . rest; | marks the bar.
extension BeatPreset {
    public static let library: [BeatPreset] = [
        // Trap
        BeatPreset("trap-classic", "Trap Classic", .trap, bpm: 140, kit: .trap808, [
            (0, "X.....x...x.....|X.....x..X..x..."), (1, "........X.......|........X......."),
            (4, "........x.......|........x......."), (2, "x.x.x.x.x.x.x3x.|x.x.x.x.x4x.x.x.")],
            bassLine: "0:0:6 6:0:4 10:0:4 16:0:6 22:0:3 25:-2:3 28:3:4"),
        BeatPreset("trap-dark", "Dark Trap", .trap, bpm: 145, kit: .trap808, bass: .dirty808, [
            (0, "X.......X.x.....|X......xX......."), (1, "........X.......|........X......."),
            (2, "xxx.xxx.xxx.x4x.|x.x.x.x.x.x.33x."), (3, "......x.........|................")],
            bassLine: "0:0:8:s 8:0:2 10:-1:4 16:0:7:s 23:1:1 24:-4:8"),
        BeatPreset("trap-melodic", "Melodic Trap", .trap, bpm: 150, kit: .trap808, [
            (0, "X.....x.........|X.....x...x....."), (1, "........X.......|........X......."),
            (2, "x.x.x.x.x.x.x.x.|x.x.x.x.x.x.3.3."), (5, "...x..........x.|...x............")],
            bassLine: "0:0:6 6:0:8 16:-4:6 22:-4:4 26:-2:6"),
        BeatPreset("trap-rage", "Rage", .trap, bpm: 160, kit: .phonk, bass: .dirty808, [
            (0, "X.....X...X...X.|X.....X...X....."), (1, "........X.......|........X......."),
            (2, "x.x.x.x.x.x.x.x.|x.x.x.x.x.x.3.x.")],
            bassLine: "0:0:6 6:0:4 10:0:4 14:-2:2 16:0:6 22:3:4 26:2:6"),
        // Drill
        BeatPreset("drill-uk", "UK Drill", .drill, bpm: 142, kit: .drill, [
            (0, "X.........X.....|..X.......X....."), (1, "........X.......|........X.....x."),
            (2, "x..x..x.x.x..x..|x..x..x.x..x.x.x"), (5, "...........x....|................")],
            bassLine: "0:0:3:s 3:7:3 6:0:4 10:-2:6:s 16:0:3:s 19:3:3:s 22:5:4 26:3:6"),
        BeatPreset("drill-ny", "NY Drill", .drill, bpm: 144, kit: .drill, [
            (0, "X..x......X..x..|X..x....X......."), (1, "........X.......|........X..x...."),
            (2, "x.xx.x.xx.x.x.x.|x.xx.x.x.x.xx.x."), (3, "..............x.|................")],
            bassLine: "0:0:3 3:0:3 10:-2:3:s 13:0:3 16:0:3 19:0:3 24:3:4:s 28:2:4"),
        // Boom bap
        BeatPreset("boombap-classic", "Boom Bap", .boomBap, bpm: 90, swing: 0.58, kit: .boomBap, bass: .fingerBass, [
            (0, "X.....x...X.....|X.x.......X..x.."), (1, "....X.......X...|....X.......X..o"),
            (2, "X.x.X.x.X.x.X.x.|X.x.X.x.X.x.X.x.")],
            bassLine: "0:0:4 6:0:2 10:3:4 16:0:4 22:-2:2 26:-5:4"),
        BeatPreset("boombap-dusty", "Dusty Break", .boomBap, bpm: 88, swing: 0.6, kit: .dusty, bass: .fingerBass, [
            (0, "X.x.......x.....|X.x....x..x....."), (1, "....X..o....X...|....X..o....X.o."),
            (2, "x.x.x.x.x.x.x.x.|x.x.x.x.x.x.x.x."), (3, "..............x.|..............x.")],
            bassLine: "0:0:3 3:0:1 10:-2:4 16:0:3 19:0:1 26:-4:4"),
        BeatPreset("boombap-jazzy", "Jazzy Boom Bap", .boomBap, bpm: 92, swing: 0.62, kit: .boomBap, bass: .fingerBass, [
            (0, "X........x......|X.x......x......"), (1, "....X.......X...|....X.......X..."),
            (10, "x...x..xx...x..x|x...x..xx...x..x"), (5, "...........x....|...........x....")],
            bassLine: "0:0:4 4:3:4 8:5:4 12:7:4 16:0:4 20:-2:4 24:-4:4 28:-5:4"),
        BeatPreset("westcoast-gfunk", "G-Funk", .westCoast, bpm: 92, swing: 0.56, kit: .coast, bass: .synthBass, [
            (0, "X......x..X.....|X.x....x..X....."), (4, "....X.......X...|....X.......X..."),
            (2, "x.x.x.x.x.x.x.x.|x.x.x.x.x.x.x.x."), (3, "..............x.|..............x.")],
            bassLine: "0:0:3 3:0:1 6:7:2 10:10:3 14:12:2 16:5:3 19:5:1 22:3:2 26:0:4"),
        BeatPreset("westcoast-electro", "Electro Funk", .electro, bpm: 115, kit: .coast, bass: .punch808, [
            (0, "X......X..X.....|X......X..X..X.."), (4, "....X.......X...|....X.......X..."),
            (2, "x.x.x.x.x.x.x.x.|x.x.x.x.x.x.x.x."), (12, "...x......x.....|...x......x.....")],
            bassLine: "0:0:2 7:0:1 10:12:2 14:10:2 16:0:2 23:0:1 26:7:2 30:3:2"),
        // Lo-fi
        BeatPreset("lofi-chill", "Lo-fi Chill", .lofi, bpm: 78, swing: 0.6, kit: .lofi, bass: .fingerBass, [
            (0, "X.......X.x.....|X.....x...x....."), (1, "....X.......X...|....X.......X..."),
            (2, "x.xox.x.x.xox.x.|x.xox.x.x.xox.x.")],
            bassLine: "0:0:6 8:-2:4 12:-4:4 16:-5:8 24:-2:6"),
        BeatPreset("lofi-rain", "Rainy Lo-fi", .lofi, bpm: 72, swing: 0.62, kit: .lofi, bass: .fingerBass, [
            (0, "X.........X.....|X.......X......."), (1, "....X.......X...|....X.......X..."),
            (14, "x.x.x.x.x.x.x.x.|x.x.x.x.x.x.x.x."), (5, "......x.........|......x.....x...")],
            bassLine: "0:0:8 8:3:8 16:-4:8 24:-2:8"),
        BeatPreset("lofi-study", "Study Beats", .lofi, bpm: 85, swing: 0.58, kit: .lofi, bass: .fingerBass, [
            (0, "X.....x.X.......|X.....x...x....."), (1, "....X.......X...|....X.......X.o."),
            (2, "x.x.x.x.x.x.x.x.|x.x.x.x.x.x.x.xx"), (15, "..........x.....|..........x...x.")],
            bassLine: "0:0:4 6:0:2 8:3:4 16:5:4 22:3:2 24:-2:6"),
        // Phonk
        BeatPreset("phonk-drift", "Drift Phonk", .phonk, bpm: 130, kit: .phonk, bass: .dirty808, [
            (0, "X.....x...X.....|X.....x...X..x.."), (4, "....X.......X...|....X.......X..."),
            (2, "x.x.x.x.x.x.x.x.|x.x.x.x.x.x.x.x."), (12, "x..x..x...x..x..|x..x..x...x.x.x."),
            (15, "........x.......|........x.......")],
            bassLine: "0:0:3 3:0:3 6:0:4 10:3:3 13:2:3 16:0:3 19:0:3 22:-2:4 26:-4:6"),
        BeatPreset("phonk-memphis", "Memphis Phonk", .phonk, bpm: 140, kit: .phonk, bass: .dirty808, [
            (0, "X......x..X.....|X......x..X..x.."), (1, "........X.......|........X......."),
            (2, "x.x.x.x.x.x.x.x.|x.x.x.x.x.x.33x."), (12, "x...............|x.......x.......")],
            bassLine: "0:0:6 7:0:3 10:1:6 16:0:6 23:0:3 26:-2:6"),
        // R&B
        BeatPreset("rnb-slow", "Slow R&B", .rnb, bpm: 70, swing: 0.55, kit: .trap808, [
            (0, "X......x..x.....|X.x....x........"), (1, "....X.......X...|....X.......X..."),
            (2, "x.x.x.x.x.x.x.x.|x.x.x.x.x.x.3.x."), (5, "..........x.....|...x......x.....")],
            bassLine: "0:0:6 7:0:3 10:3:6 16:-4:6 23:-4:3 26:-2:6"),
        BeatPreset("rnb-neo", "Neo Soul", .rnb, bpm: 88, swing: 0.64, kit: .lofi, bass: .fingerBass, [
            (0, "X.......x.x.....|X..x......x....."), (1, "....X.......X...|....X.......X..."),
            (2, "x.xxx.xxx.xxx.xx|x.xxx.xxx.xxx.x.")],
            bassLine: "0:0:3 3:7:3 6:0:2 10:10:3 13:7:3 16:5:3 19:3:3 22:0:6"),
        // Pop
        BeatPreset("pop-four", "Pop Four", .pop, bpm: 120, kit: .house, bass: .synthBass, minor: false, [
            (0, "X...X...X...X..."), (1, "....X.......X..."), (4, "....x.......x..."), (2, "..x...x...x...x.")],
            bassLine: "0:0:2 2:0:2 4:0:2 6:0:2 8:-5:2 10:-5:2 12:-3:2 14:-3:2"),
        BeatPreset("pop-dance", "Dance Pop", .pop, bpm: 124, kit: .house, bass: .synthBass, minor: false, [
            (0, "X...X...X...X...|X...X...X...X..."), (4, "....X.......X...|....X.......X..."),
            (3, "..x...x...x...x.|..x...x...x...x."), (2, "x.x.x.x.x.x.x.x.|x.x.x.x.x.x.x.x.")],
            bassLine: "2:0:2 6:0:2 10:0:2 14:0:2 18:-3:2 22:-3:2 26:-5:2 30:-5:2"),
        // House and techno
        BeatPreset("house-deep", "Deep House", .house, bpm: 122, swing: 0.54, kit: .house, bass: .synthBass, [
            (0, "X...X...X...X...|X...X...X...X..."), (4, "....X.......X...|....X.......X..."),
            (3, "..x...x...x...x.|..x...x...x...x."), (14, "xoxoxoxoxoxoxoxo|xoxoxoxoxoxoxoxo")],
            bassLine: "3:0:2 6:0:1 10:0:3 14:7:2 19:0:2 22:-2:1 26:-4:3 30:-2:2"),
        BeatPreset("house-classic", "Classic House", .house, bpm: 125, kit: .house, bass: .synthBass, [
            (0, "X...X...X...X..."), (4, "....X.......X..."), (3, "..x...x...x...x."),
            (2, "x.x.x.x.x.x.x.x."), (5, "...x......x.....")],
            bassLine: "2:0:2 6:0:2 10:0:2 14:5:2"),
        BeatPreset("house-tech", "Tech House", .house, bpm: 126, kit: .techno, bass: .synthBass, [
            (0, "X...X...X...X..."), (4, "....X.......X..."), (3, "..x...x...x...x."),
            (2, "x.xxx.xxx.xxx.xx"), (15, "......x.......x.")],
            bassLine: "2:0:1 3:0:1 6:0:2 10:0:1 11:0:1 14:3:2"),
        BeatPreset("techno-drive", "Techno Drive", .techno, bpm: 130, kit: .techno, bass: .synthBass, [
            (0, "X...X...X...X..."), (4, "....X.......X..."), (3, "..x...x...x...x."), (2, "XxxxXxxxXxxxXxxx")],
            bassLine: "2:0:2 6:0:2 10:0:2 14:0:2"),
        BeatPreset("techno-acid", "Acid Line", .techno, bpm: 132, kit: .techno, bass: .acid, [
            (0, "X...X...X...X..."), (4, "....x.......x..."), (2, "..x...x...x...x."), (10, "x.x.x.x.x.x.x.x.")],
            bassLine: "0:0:1 2:12:1 3:0:1 5:0:1 6:10:1 8:0:1 10:7:1 11:0:1 13:3:2 15:12:1"),
        // UK garage, drum & bass, bass music
        BeatPreset("garage-2step", "2-Step", .garage, bpm: 132, swing: 0.6, kit: .garage, bass: .reese, [
            (0, "X.........X.....|X......x..X....."), (1, "....X.......X...|....X.......X..."),
            (2, "..x...x...x...x.|..x...x...x.x.x."), (14, "xoxoxoxoxoxoxoxo|xoxoxoxoxoxoxoxo")],
            bassLine: "0:0:4 6:0:2 10:-2:4 16:0:4 22:3:2 26:-4:4"),
        BeatPreset("garage-speed", "Speed Garage", .garage, bpm: 134, swing: 0.56, kit: .garage, bass: .reese, [
            (0, "X...X...X...X..."), (4, "....X.......X..."), (3, "..x...x...x...x."), (2, "x.x.x.x.x.x.x.x.")],
            bassLine: "2:0:2 6:0:1 7:12:1 10:0:2 14:0:1 15:12:1"),
        BeatPreset("dnb-liquid", "Liquid DnB", .dnb, bpm: 174, kit: .jungle, bass: .reese, [
            (0, "X.........X.....|X.x.......X....."), (1, "....X.......X...|....X.......X..o"),
            (2, "x.x.x.x.x.x.x.x.|x.x.x.x.x.x.x.x.")],
            bassLine: "0:0:8 10:-2:6 16:-4:8 26:-5:6"),
        BeatPreset("dnb-jungle", "Jungle Break", .dnb, bpm: 170, kit: .jungle, bass: .reese, [
            (0, "X.........X.....|..X.......X....."), (1, "....X..o.o..X...|....X..o.o..X.o."),
            (2, "x.x.x.xxx.x.x.xx|x.x.xx.xx.x.x.x."), (15, "..o.......o.....|.o......o.......")],
            bassLine: "0:0:6 6:3:4 10:-2:6 16:0:6 22:5:4 26:3:6"),
        BeatPreset("bass-halftime", "Half-time Bass", .bass, bpm: 140, kit: .drill, bass: .reese, [
            (0, "X.........X.....|X..x......X....."), (1, "........X.......|........X......."),
            (2, "x...x...x...x...|x...x...x.x.x.x.")],
            bassLine: "0:0:6 6:0:2 10:-2:6 16:3:6 22:3:2 26:-4:6"),
        // Latin, afro and club
        BeatPreset("reggaeton-dembow", "Dembow", .reggaeton, bpm: 95, kit: .reggaeton, [
            (0, "X...X...X...X...|X...X...X...X..."), (1, "...x..x....x..x.|...x..x....x..x."),
            (2, "x.x.x.x.x.x.x.x.|x.x.x.x.x.x.x.x."), (15, "..............xx|..............xx")],
            bassLine: "0:0:3 3:0:1 4:0:3 8:-4:3 11:-4:1 12:-4:3 16:-2:3 19:-2:1 20:-2:3 24:-5:3 27:-5:1 28:-5:3"),
        BeatPreset("reggaeton-perreo", "Perreo", .reggaeton, bpm: 98, kit: .reggaeton, [
            (0, "X...X...X...X...|X...X...X...X..."), (1, "...x..x....x..x.|...x..x....x..x."),
            (4, "....x.......x...|....x.......x..."), (3, "..x...x...x...x.|..x...x...x...x.")],
            bassLine: "0:0:2 3:0:1 6:0:2 8:3:2 11:3:1 14:3:2 16:-2:2 19:-2:1 22:-2:2 24:-4:2 27:-4:1 30:-4:2"),
        BeatPreset("afro-bounce", "Afro Bounce", .afro, bpm: 105, swing: 0.56, kit: .afro, [
            (0, "X.....x...X.....|X..x..x...X....."), (5, "...x..x....x..x.|...x..x....x...x"),
            (4, "....x.......x...|....x.......x..."), (14, "x.xxx.xxx.xxx.xx|x.xxx.xxx.xxx.xx"),
            (15, "..........x.x...|..........x.x...")],
            bassLine: "0:0:3 6:0:2 10:-2:3 14:0:2 16:3:3 22:3:2 26:-2:3 30:0:2"),
        BeatPreset("afro-amapiano", "Amapiano", .afro, bpm: 112, kit: .afro, bass: .logDrum, [
            (0, "X...X...X...X...|X...X...X...X..."), (4, "........x.......|........x......."),
            (14, "xoxoxoxoxoxoxoxo|xoxoxoxoxoxoxoxo"), (5, "..x..x....x..x..|..x..x....x..x..")],
            bassLine: "3:0:2 6:7:2 11:5:2 14:3:2 19:0:2 22:-2:2 27:-4:3"),
        BeatPreset("jersey-bounce", "Jersey Bounce", .jersey, bpm: 140, kit: .trap808, [
            (0, "X...X...X.X.X...|X...X...X.X.X.X."), (4, "....X.......X...|....X.......X..."),
            (2, "x.x.x.x.x.x.x.x.|x.x.x.x.x.x.x.x."), (15, "......x.......x.|......x.......x.")],
            bassLine: "0:0:2 8:0:2 10:0:2 12:-2:2 16:0:2 24:3:2 26:3:2 28:5:2"),
        // Funk, disco and band styles
        BeatPreset("funk-groove", "Funk Groove", .funk, bpm: 105, swing: 0.54, kit: .dusty, bass: .fingerBass, [
            (0, "X.x.....x.x....."), (1, "....X..o.o..X..o"), (2, "x.xxx.xxx.xxx.xx")],
            bassLine: "0:0:2 3:12:1 4:0:1 6:10:2 8:0:1 10:7:2 12:0:2 14:3:2"),
        BeatPreset("funk-disco", "Disco Night", .funk, bpm: 118, kit: .house, bass: .fingerBass, minor: false, [
            (0, "X...X...X...X..."), (4, "....X.......X..."), (3, "..x...x...x...x."),
            (2, "x.x.x.x.x.x.x.x."), (11, "....x.......x...")],
            bassLine: "0:0:2 2:12:2 4:0:2 6:12:2 8:5:2 10:17:2 12:5:2 14:17:2"),
        BeatPreset("rock-beat", "Rock Beat", .rock, bpm: 120, kit: .rock, bass: .fingerBass, minor: false, [
            (0, "X.....X.X.......|X.....X.X....x.."), (1, "....X.......X...|....X.......X..."),
            (2, "x.x.x.x.x.x.x.x.|x.x.x.x.x.x.x.x."), (9, "x...............|................")],
            bassLine: "0:0:2 2:0:2 4:0:2 6:0:2 8:0:2 10:0:2 12:5:2 14:5:2 16:7:2 18:7:2 20:7:2 22:7:2 24:5:2 26:5:2 28:5:2 30:5:2"),
        BeatPreset("rock-punk", "Punk Drive", .rock, bpm: 170, kit: .rock, bass: .fingerBass, minor: false, [
            (0, "X.....X.X.....X."), (1, "....X.......X..."), (2, "x.x.x.x.x.x.x.x."), (9, "x...............")],
            bassLine: "0:0:2 2:0:2 4:0:2 6:0:2 8:5:2 10:5:2 12:7:2 14:7:2"),
        BeatPreset("rock-stomp", "Stadium Stomp", .rock, bpm: 92, kit: .rock, bass: .fingerBass, minor: false, [
            (0, "X.......X.......|X.......X......."), (1, "....X.......X...|....X.......X..."),
            (4, "....x.......x...|....x.......x..."), (9, "x...............|................"),
            (7, "................|..........x.x..."), (8, "................|........x.x.....")],
            bassLine: "0:0:8 8:0:8 16:-3:8 24:-5:8"),
        // Synthwave and chiptune
        BeatPreset("synthwave-drive", "Night Drive", .synthwave, bpm: 100, kit: .synthwave, bass: .synthBass, [
            (0, "X.......X.......|X.......X.x....."), (1, "....X.......X...|....X.......X..."),
            (2, "x.x.x.x.x.x.x.x.|x.x.x.x.x.x.x.x.")],
            bassLine: "0:0:1 2:0:1 4:0:1 6:0:1 8:0:1 10:0:1 12:0:1 14:0:1 16:-4:1 18:-4:1 20:-4:1 22:-4:1 24:-2:1 26:-2:1 28:-2:1 30:-2:1"),
        BeatPreset("synthwave-outrun", "Outrun", .synthwave, bpm: 118, kit: .synthwave, bass: .synthBass, [
            (0, "X...X...X...X...|X...X...X...X..."), (1, "....X.......X...|....X.......X..."),
            (3, "..x...x...x...x.|..x...x...x...x."), (8, "................|............x.x."), (7, "................|..............xx")],
            bassLine: "0:0:1 1:12:1 2:0:1 3:12:1 4:0:1 5:12:1 6:0:1 7:12:1 8:0:1 9:12:1 10:0:1 11:12:1 12:0:1 13:12:1 14:0:1 15:12:1 16:-4:1 17:8:1 18:-4:1 19:8:1 20:-4:1 21:8:1 22:-4:1 23:8:1 24:-2:1 25:10:1 26:-2:1 27:10:1 28:-2:1 29:10:1 30:-2:1 31:10:1"),
        BeatPreset("chip-adventure", "8-bit Adventure", .chiptune, bpm: 150, kit: .chip, bass: .synthBass, [
            (0, "X.......X.x.....|X.......X......."), (1, "....X.......X...|....X.......X.xx"),
            (2, "x.x.x.x.x.x.x.x.|x.x.x.x.x.x.x.x.")],
            bassLine: "0:0:2 2:12:2 4:0:2 6:12:2 8:-4:2 10:8:2 12:-2:2 14:10:2 16:0:2 18:12:2 20:0:2 22:12:2 24:3:2 26:15:2 28:-2:2 30:10:2"),
        // Jazz and world
        BeatPreset("jazz-brushes", "Brush Swing", .jazz, bpm: 120, swing: 0.6, kit: .brushes, bass: .fingerBass, minor: false, [
            (0, "o...o...o...o...|o...o...o...o..."), (1, "....x.......x...|....x.......x..."),
            (10, "x...x..xx...x..x|x...x..xx...x..x")],
            bassLine: "0:0:4 4:4:4 8:7:4 12:9:4 16:5:4 20:9:4 24:7:4 28:2:4"),
        BeatPreset("jazz-bossa", "Bossa Groove", .jazz, bpm: 130, kit: .brushes, bass: .fingerBass, minor: false, [
            (0, "X..xX..xX..xX..x|X..xX..xX..xX..x"), (5, "x..x..x...x..x..|..x..x...x..x..."),
            (2, "x.x.x.x.x.x.x.x.|x.x.x.x.x.x.x.x.")],
            bassLine: "0:0:3 3:7:1 4:7:4 8:0:3 11:7:1 12:7:4 16:5:3 19:0:1 20:0:4 24:7:3 27:2:1 28:2:4"),
        BeatPreset("world-desert", "Desert Groove", .world, bpm: 100, kit: .world, bass: .fingerBass, [
            (0, "X.....X...X.....|X..x..X...X....."), (1, "...x..x.....x...|...x..x.....x.x."),
            (15, ".x.......x......|.x.......x......"), (14, "x.xxx.xxx.xxx.xx|x.xxx.xxx.xxx.xx")],
            bassLine: "0:0:3 6:1:3 10:0:3 13:-2:3 16:0:3 22:1:3 26:3:3 29:1:3"),
    ]
}

// MARK: - Editable draft

/// One step of a pad lane.
public enum StepHit: Equatable, Sendable {
    case off, ghost, normal, accent, roll(Int)

    public init(_ character: Character) {
        switch character {
        case "X": self = .accent
        case "x": self = .normal
        case "o": self = .ghost
        case "2", "3", "4": self = .roll(Int(String(character)) ?? 2)
        default: self = .off
        }
    }

    public var velocity: Int {
        switch self {
        case .off: 0
        case .ghost: 54
        case .normal: 100
        case .accent: 122
        case .roll: 94
        }
    }

    public var isOn: Bool { self != .off }
}

/// A bass or 808 note in sixteenth steps, semitones from the key's root.
public struct BassStep: Equatable, Sendable {
    public var step: Int
    public var semitones: Int
    public var length: Int
    /// The note slides into the next one (808 glide).
    public var slide: Bool
    public init(step: Int, semitones: Int, length: Int, slide: Bool = false) { self.step = step; self.semitones = semitones; self.length = length; self.slide = slide }
}

/// The beat being shaped in the beat machine. Changes stay here until Apply.
public struct BeatDraft: Equatable, Sendable {
    public static let semitoneRange = -12...24
    public var presetID: String
    public var bpm: Int
    public var swing: Double
    public var kit: FactoryDrumKit
    public var bass: FactorySynth?
    /// Sixteenth steps: 16 (one bar) or 32 (two bars).
    public private(set) var steps: Int
    /// Pad → one hit per step.
    public private(set) var grid: [Int: [StepHit]]
    public private(set) var bassNotes: [BassStep]
    public let minor: Bool

    public init(_ preset: BeatPreset) {
        presetID = preset.id; bpm = preset.bpm; swing = preset.swing; kit = preset.kit; bass = preset.bass; minor = preset.minor
        steps = preset.steps
        var grid: [Int: [StepHit]] = [:]
        for lane in preset.lanes { grid[lane.pad] = BeatPreset.clean(lane.steps).map(StepHit.init) }
        self.grid = grid
        bassNotes = Self.parseBass(preset.bassLine, steps: preset.steps)
    }

    /// An empty one-bar beat on a kit.
    public init(kit: FactoryDrumKit = .trap808, bpm: Int = 140) {
        presetID = "empty"; self.bpm = bpm; swing = 0.5; self.kit = kit; bass = .sub808; minor = true
        steps = 16; grid = [:]; bassNotes = []
    }

    /// "step:semitones:length" with an optional ":s" for a slide into the next note.
    public static func parseBass(_ text: String, steps: Int) -> [BassStep] {
        text.split(separator: " ").compactMap { token in
            let fields = token.split(separator: ":")
            let slide = fields.count == 4 && fields[3] == "s"
            let parts = fields.prefix(3).compactMap { Int($0) }
            guard parts.count == 3, fields.count == 3 || slide, (0..<steps).contains(parts[0]), semitoneRange.contains(parts[1]), parts[2] >= 1 else { return nil }
            return BassStep(step: parts[0], semitones: parts[1], length: min(parts[2], steps - parts[0]), slide: slide)
        }.sorted { $0.step < $1.step }
    }

    public var hasSlides: Bool { bassNotes.contains(where: \.slide) }

    /// Turns the slide of the note that starts at `step` on or off.
    public mutating func toggleSlide(step: Int) {
        guard let index = bassNotes.firstIndex(where: { $0.step == step }) else { return }
        bassNotes[index].slide.toggle()
    }

    public var bars: Int { steps / 16 }

    public func hit(pad: Int, step: Int) -> StepHit {
        guard let lane = grid[pad], lane.indices.contains(step) else { return .off }
        return lane[step]
    }

    /// Pads that play at least once, in pad order.
    public var activePads: [Int] { grid.keys.filter { grid[$0]?.contains(where: \.isOn) == true }.sorted() }

    public var hitCount: Int { grid.values.reduce(0) { $0 + $1.filter(\.isOn).count } }

    public mutating func set(pad: Int, step: Int, _ hit: StepHit) {
        guard (0..<16).contains(pad), (0..<steps).contains(step) else { return }
        var lane = grid[pad] ?? Array(repeating: .off, count: steps)
        lane[step] = hit
        grid[pad] = lane.contains(where: \.isOn) ? lane : nil
    }

    /// Tap: an empty step gets a hit, a filled one empties.
    public mutating func toggle(pad: Int, step: Int) {
        set(pad: pad, step: step, hit(pad: pad, step: step).isOn ? .off : .normal)
    }

    /// The bass note sounding at a step (started there or still held).
    public func bassNote(at step: Int) -> BassStep? {
        bassNotes.first { $0.step <= step && step < $0.step + $0.length }
    }

    /// Tap on the bass lane: removes the note under the step, or starts one there that
    /// lasts until the next note (at most two steps) on the last pitch used.
    public mutating func toggleBass(step: Int, semitones: Int? = nil) {
        guard (0..<steps).contains(step) else { return }
        if let index = bassNotes.firstIndex(where: { $0.step <= step && step < $0.step + $0.length }) {
            bassNotes.remove(at: index); return
        }
        let next = bassNotes.first { $0.step > step }?.step ?? steps
        let pitch = semitones ?? bassNotes.last { $0.step < step }?.semitones ?? 0
        bassNotes.append(BassStep(step: step, semitones: max(Self.semitoneRange.lowerBound, min(Self.semitoneRange.upperBound, pitch)), length: max(1, min(2, next - step))))
        bassNotes.sort { $0.step < $1.step }
    }

    /// Moves the note that starts at `step` by `delta` semitones within the range.
    public mutating func transposeBass(step: Int, by delta: Int) {
        guard let index = bassNotes.firstIndex(where: { $0.step == step }) else { return }
        bassNotes[index].semitones = max(Self.semitoneRange.lowerBound, min(Self.semitoneRange.upperBound, bassNotes[index].semitones + delta))
    }

    /// Makes the note that starts at `step` last `length` steps, up to the next note.
    public mutating func setBassLength(step: Int, _ length: Int) {
        guard let index = bassNotes.firstIndex(where: { $0.step == step }) else { return }
        let next = bassNotes.first { $0.step > step }?.step ?? steps
        bassNotes[index].length = max(1, min(length, next - step))
    }

    /// One bar ↔ two bars. Going to two copies the first bar; going to one drops the second.
    public mutating func setBars(_ bars: Int) {
        let target = bars >= 2 ? 32 : 16
        guard target != steps else { return }
        if target > steps {
            grid = grid.mapValues { $0 + $0 }
            bassNotes += bassNotes.map { BassStep(step: $0.step + 16, semitones: $0.semitones, length: $0.length) }
        } else {
            grid = grid.compactMapValues { lane in
                let first = Array(lane.prefix(16))
                return first.contains(where: \.isOn) ? first : nil
            }
            bassNotes = bassNotes.filter { $0.step < 16 }.map { BassStep(step: $0.step, semitones: $0.semitones, length: min($0.length, 16 - $0.step)) }
        }
        steps = target
    }

    public mutating func clear() { grid = [:]; bassNotes = [] }

    /// Same groove, new details: a few ghost notes, hat rolls and kick pickups come and go.
    /// The kick on the downbeat and the backbeat stay where they are.
    public mutating func vary(seed: UInt64) {
        var random = SeededRandom(seed: seed)
        for pad in [2, 14] where grid[pad] != nil {
            for step in 0..<steps where step % 4 == 2 || step % 4 == 3 {
                let current = hit(pad: pad, step: step)
                if current.isOn && random.chance(0.25) { set(pad: pad, step: step, current == .normal ? .roll(random.chance(0.5) ? 2 : 3) : .normal) }
                else if !current.isOn && random.chance(0.12) { set(pad: pad, step: step, .ghost) }
            }
        }
        if grid[0] != nil {
            for step in 0..<steps where step % 8 != 0 {
                let current = hit(pad: 0, step: step)
                if !current.isOn && step % 2 == 1 && random.chance(0.08) { set(pad: 0, step: step, .ghost) }
                else if current == .ghost && random.chance(0.5) { set(pad: 0, step: step, .off) }
            }
        }
        let snare = grid[1] != nil ? 1 : 4
        for step in 0..<steps where step % 4 != 0 && !hit(pad: snare, step: step).isOn && random.chance(0.06) {
            set(pad: snare, step: step, .ghost)
        }
    }

    // MARK: Rendering to events

    static func swingOffset(_ step: Int, swing: Double) -> Int {
        step % 2 == 1 ? Int(((max(0.5, min(0.75, swing)) - 0.5) * 480).rounded()) : 0
    }

    public var length: Int { bars * barTicks }

    public func drumEvents() -> [DrumEvent] {
        var events: [DrumEvent] = []
        for pad in grid.keys.sorted() {
            for (step, hit) in (grid[pad] ?? []).enumerated() where hit.isOn {
                var event = DrumEvent(tick: step * 240 + Self.swingOffset(step, swing: swing), pad: pad, velocity: hit.velocity)
                if case let .roll(count) = hit { event.ratchet = max(2, min(4, count)) }
                events.append(event)
            }
        }
        return events.sorted { $0.tick == $1.tick ? $0.pad < $1.pad : $0.tick < $1.tick }
    }

    /// The root note of the bass register for a key: F1…E2.
    public static func bassRoot(keyRoot: Int) -> Int { let pitch = 36 + ((keyRoot % 12) + 12) % 12; return pitch > 40 ? pitch - 12 : pitch }

    /// Semitones written in one mode, moved to the song's mode (third, sixth and seventh).
    public static func fitted(_ semitones: Int, writtenMinor: Bool, songMinor: Bool) -> Int {
        guard writtenMinor != songMinor else { return semitones }
        let octave = Int((Double(semitones) / 12).rounded(.down)), degree = semitones - octave * 12
        let map: [Int: Int] = writtenMinor ? [3: 4, 8: 9] : [4: 3, 9: 8, 11: 10]
        return octave * 12 + (map[degree] ?? degree)
    }

    public func bassEvents(keyRoot: Int, minor songMinor: Bool) -> [NoteEvent] {
        let root = Self.bassRoot(keyRoot: keyRoot)
        return bassNotes.enumerated().map { index, note in
            let start = note.step * 240 + Self.swingOffset(note.step, swing: swing)
            let end = min(length, (note.step + note.length) * 240 + Self.swingOffset(note.step + note.length, swing: swing))
            let pitch = max(0, min(127, root + Self.fitted(note.semitones, writtenMinor: minor, songMinor: songMinor)))
            // A slide holds on into the next note so the engine bends instead of re-striking.
            if note.slide, index + 1 < bassNotes.count {
                let next = bassNotes[index + 1].step * 240 + Self.swingOffset(bassNotes[index + 1].step, swing: swing)
                return NoteEvent(tick: start, duration: max(30, min(length - start, next - start + 60)), pitch: pitch, velocity: 108)
            }
            return NoteEvent(tick: start, duration: max(30, end - start - 12), pitch: pitch, velocity: 108)
        }
    }
}

// MARK: - Applying to a song

public enum BeatMachine {
    public enum Scope: Equatable, Sendable { case section(UUID), song }

    public struct Options: Equatable, Sendable {
        /// Take the beat's tempo.
        public var useTempo: Bool
        /// Silence the bass that follows the chords while the 808 plays.
        public var muteChordBass: Bool
        public init(useTempo: Bool = true, muteChordBass: Bool = true) { self.useTempo = useTempo; self.muteChordBass = muteChordBass }
    }

    public enum BeatError: Error, LocalizedError, Equatable {
        case drumsLocked, bassLocked, empty
        public var errorDescription: String? {
            let key = switch self {
            case .drumsLocked: "The drums track is locked. Unlock it in the mixer to put a new beat there."
            case .bassLocked: "The 808 track is locked. Unlock it in the mixer to change its notes."
            case .empty: "The beat has no hits yet. Tap a few steps first."
            }
            return NSLocalizedString(key, comment: "Beat machine")
        }
    }

    /// Name of the melodic track that carries the 808 or bass line.
    public static let bassTrackName = "808"

    public static func bassTrack(in project: Project) -> Int? {
        project.tracks.firstIndex { $0.role == .melody && $0.name == bassTrackName }
    }

    /// The song with the beat in place; the source stays untouched. `kit` holds the 16 pad
    /// assets of `draft.kit`; `bass` is the instrument asset of `draft.bass`.
    public static func candidate(_ project: Project, draft: BeatDraft, scope: Scope, kit: [Int: SampleAsset],
                                 bass: SampleAsset?, options: Options = Options()) throws -> Project {
        try project.validate()
        guard draft.hitCount > 0 || !draft.bassNotes.isEmpty else { throw BeatError.empty }
        guard kit.count == 16 else { throw SampleError.invalid }
        var result = project
        let sections: [Section]
        switch scope {
        case .song: sections = project.sections
        case .section(let id):
            guard let section = project.sections.first(where: { $0.id == id }) else { throw MusicError.invalidProject }
            sections = [section]
        }
        let length = min(draft.length, project.length)
        if draft.hitCount > 0 {
            guard result.tracks[1].locked != true else { throw BeatError.drumsLocked }
            let events = draft.drumEvents().filter { $0.tick < length }
            for section in sections {
                var pattern = Pattern(length: length)
                pattern.drums = events.map { var copy = $0; copy.id = UUID(); return copy }
                place(pattern, on: 1, section: section, in: &result)
            }
            result.tracks[1].padSamples = kit
            result.tracks[1].padEdits = nil
            result.tracks[1].mutedPads = nil
        }
        if let bass, draft.bass != nil, !draft.bassNotes.isEmpty {
            var index = bassTrack(in: result)
            if index == nil { try result.addMelody(name: bassTrackName); index = result.tracks.indices.last }
            guard let track = index else { throw MusicError.invalidProject }
            guard result.tracks[track].locked != true else { throw BeatError.bassLocked }
            let notes = draft.bassEvents(keyRoot: project.keyRoot, minor: project.minor).filter { $0.tick < length }
            for section in sections {
                var pattern = Pattern(length: length)
                pattern.notes = notes.map { var copy = $0; copy.id = UUID(); copy.duration = min(copy.duration, length - copy.tick); return copy }
                place(pattern, on: track, section: section, in: &result)
            }
            result.tracks[track].instrumentSample = bass
            result.tracks[track].synth = nil
            // Slides need the engine's glide on the 808 track.
            result.tracks[track].glide = draft.hasSlides ? 0.07 : nil
            if options.muteChordBass {
                for other in result.tracks.indices where result.tracks[other].role == .bass { result.tracks[other].mute = true }
            }
        }
        if options.useTempo { result.bpm = Double(max(40, min(240, draft.bpm))) }
        result.removeUnusedPatterns()
        try result.validate()
        return result
    }

    /// Replaces whatever the track plays inside the section with one clip of `pattern`.
    static func place(_ pattern: Pattern, on track: Int, section: Section, in project: inout Project) {
        let start = section.start, end = section.start + section.length
        var clips: [Clip] = []
        for clip in project.tracks[track].clips {
            let clipEnd = clip.start + clip.length
            guard clip.start < end && clipEnd > start else { clips.append(clip); continue }
            if clip.start < start {
                var before = clip; before.length = start - clip.start; clips.append(before)
            }
            if clipEnd > end, let source = project.patterns.first(where: { $0.id == clip.patternID }) {
                var after = clip
                after.id = UUID(); after.start = end; after.length = clipEnd - end
                after.offset = (clip.offset + (end - clip.start)) % max(1, source.length)
                clips.append(after)
            }
        }
        project.patterns.append(pattern)
        clips.append(Clip(patternID: pattern.id, start: start, length: section.length))
        project.tracks[track].clips = clips.sorted { $0.start < $1.start }
    }
}
