import Foundation

struct SoundBankProgram: Hashable, Sendable {
    let name: String
    let program: UInt8
    let bank: UInt16

    var bankMSB: UInt8 { bank == 128 ? 0x78 : 0x79 }
    var bankLSB: UInt8 { bank == 128 ? 0 : UInt8(bank) }
}

/// Reads the RIFF preset headers. AVAudioUnitSampler decodes the actual bank.
enum SoundFontProgramTable {
    static func read(_ data: Data) throws -> [SoundBankProgram] {
        func tag(_ index: Int, _ value: String) -> Bool {
            data[index..<index + 4].elementsEqual(value.utf8)
        }
        func word(_ index: Int) -> Int { Int(data[index]) | (Int(data[index + 1]) << 8) }
        func size(_ index: Int) -> Int { word(index) | (word(index + 2) << 16) }
        func chunks(in range: Range<Int>, visit: (Int, Range<Int>) throws -> Void) throws {
            var offset = range.lowerBound
            while offset < range.upperBound {
                guard range.upperBound - offset >= 8 else { throw SoundFontTableError.invalid }
                let start = offset + 8
                let length = size(offset + 4)
                guard length + length % 2 <= range.upperBound - start else { throw SoundFontTableError.invalid }
                let end = start + length
                try visit(offset, start..<end)
                offset = end + length % 2
            }
        }
        guard data.startIndex == 0, data.count >= 12, tag(0, "RIFF"), tag(8, "sfbk"),
              size(4) == data.count - 8 else { throw SoundFontTableError.invalid }

        var headers: Range<Int>?
        try chunks(in: 12..<data.count) { offset, range in
            guard tag(offset, "LIST"), range.count >= 4, tag(range.lowerBound, "pdta") else { return }
            try chunks(in: range.lowerBound + 4..<range.upperBound) { offset, range in
                guard tag(offset, "phdr") else { return }
                guard headers == nil else { throw SoundFontTableError.invalid }
                headers = range
            }
        }
        let record = 38
        guard let headers, headers.count % record == 0, (2...4097).contains(headers.count / record) else {
            throw SoundFontTableError.invalid
        }
        let last = headers.upperBound - record
        guard data[last..<last + 4].elementsEqual([69, 79, 80, 0]) else { throw SoundFontTableError.invalid }
        var programs: [SoundBankProgram] = []
        var identifiers = Set<Int>()
        for offset in stride(from: headers.lowerBound, to: last, by: record) {
            let program = word(offset + 20), bank = word(offset + 22)
            guard program <= 127, bank <= 128, identifiers.insert(bank * 128 + program).inserted else { continue }
            let nameBytes = data[offset..<offset + 20].prefix { $0 != 0 }
            let name = String(decoding: nameBytes, as: UTF8.self)
                .components(separatedBy: CharacterSet.controlCharacters).joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            programs.append(SoundBankProgram(name: name.isEmpty ? String(program + 1) : name,
                                             program: UInt8(program), bank: UInt16(bank)))
        }
        guard !programs.isEmpty else { throw SoundFontTableError.invalid }
        return programs.sorted { ($0.bank, $0.program) < ($1.bank, $1.program) }
    }
}

enum SoundFontTableError: Error { case invalid }
