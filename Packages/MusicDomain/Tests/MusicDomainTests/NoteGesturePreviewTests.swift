import Foundation
import Testing
@testable import MusicDomain

struct NoteGesturePreviewTests {
    private let barWidth = 240.0, length = 4 * barTicks
    private func note(_ tick: Int = 960, _ duration: Int = 480) -> NoteEvent { NoteEvent(tick: tick, duration: duration, pitch: 60) }
    private func committed(_ original: NoteEvent, duration: Int, step: Int) -> NoteEvent {
        var p = Pattern(length: length, notes: [original]); NoteEditing.resize(original.id, in: &p, duration: duration, step: step); return p.notes![0]
    }

    @Test func everyDragPositionPreviewsExactlyTheNoteThatIsCommitted() {
        let original = note()
        for step in [60, 120, 240, 480, 960] {
            for x in stride(from: -400.0, through: 900.0, by: 7.5) {
                let preview = NoteGesturePreview.preview(original, operation: .resize, patternLength: length, translationX: x, translationY: 0, barWidth: barWidth, step: step)
                let moves = NoteGesturePreview.steps(translationX: x, barWidth: barWidth, step: step, patternLength: length)
                let saved = moves == 0 ? original : committed(original, duration: original.duration + moves * step, step: step)
                #expect(preview == saved)
                #expect(preview.duration >= 1 && preview.tick + preview.duration <= length)
                #expect(preview.tick == original.tick && preview.pitch == original.pitch && preview.id == original.id)
            }
        }
    }
    @Test func minimumStepAndBothEdgesAreRespected() {
        let original = note(960, 480)
        let shortest = NoteGesturePreview.preview(original, operation: .resize, patternLength: length, translationX: -10_000, translationY: 0, barWidth: barWidth, step: 240)
        #expect(shortest.duration == 240)
        let longest = NoteGesturePreview.preview(original, operation: .resize, patternLength: length, translationX: 10_000, translationY: 0, barWidth: barWidth, step: 240)
        #expect(longest.tick + longest.duration == length)
        let edge = note(length - 240, 240)
        let atRight = NoteGesturePreview.preview(edge, operation: .resize, patternLength: length, translationX: 500, translationY: 0, barWidth: barWidth, step: 240)
        #expect(atRight.duration == 240)
        let atLeft = NoteGesturePreview.preview(note(0, 960), operation: .move, patternLength: length, translationX: -500, translationY: 0, barWidth: barWidth, step: 240)
        #expect(atLeft.tick == 0)
    }
    @Test func invalidGeometryAndZeroMovementKeepTheOriginal() {
        let original = note()
        for width in [0.0, -1, .nan, .infinity] {
            #expect(NoteGesturePreview.preview(original, operation: .resize, patternLength: length, translationX: 300, translationY: 0, barWidth: width, step: 240) == original)
        }
        #expect(NoteGesturePreview.preview(original, operation: .resize, patternLength: length, translationX: 300, translationY: .nan, barWidth: barWidth, step: 240) == original)
        #expect(NoteGesturePreview.preview(original, operation: .resize, patternLength: length, translationX: 5, translationY: 0, barWidth: barWidth, step: 240) == original)
    }
    @Test func moveStaysInTheVisiblePitchRows() {
        let moved = NoteGesturePreview.preview(note(), operation: .move, patternLength: length, translationX: 0, translationY: -24 * 40, barWidth: barWidth, step: 240, visiblePitches: 48...71)
        #expect(moved.pitch == 71)
    }
    @Test func readoutIsAboveTheFingerOrBesideItAndNeverUnderIt() {
        let size = (w: 120.0, h: 44.0), content = (w: 960.0, h: 576.0)
        // Middle rows: above the finger.
        let middle = NoteGesturePreview.readoutCenter(finger: .init(x: 400, y: 300), noteMinY: 290, readoutWidth: size.w, readoutHeight: size.h, contentWidth: content.w, contentHeight: content.h)
        #expect(middle.y + size.h / 2 <= 300 - 34)
        // Top row: level with the finger, to the side, not covering it.
        for fingerX in [30.0, 400, 940] {
            let top = NoteGesturePreview.readoutCenter(finger: .init(x: fingerX, y: 14), noteMinY: 4, readoutWidth: size.w, readoutHeight: size.h, contentWidth: content.w, contentHeight: content.h)
            let covers = abs(top.x - fingerX) < size.w / 2 + 20 && abs(top.y - 14) < size.h / 2 + 20
            #expect(!covers || content.w < size.w * 2)
            #expect(top.x - size.w / 2 >= 0 && top.x + size.w / 2 <= content.w)
            #expect(top.y - size.h / 2 >= 0)
            #expect(top.y <= 14 + size.h / 2)
        }
    }
}
