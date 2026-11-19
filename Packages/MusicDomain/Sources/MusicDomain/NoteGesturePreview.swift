import Foundation

/// Build 44: the note drawn under the finger is computed by the same functions
/// that commit it, so the preview, playback after release and the saved note
/// agree. Geometry is plain Double to keep the model independent of UIKit.
public enum NoteGesturePreview {
    public enum Operation: Sendable { case move, resize }

    /// Whole grid steps for a horizontal translation, bounded to the pattern.
    public static func steps(translationX: Double, barWidth: Double, step: Int, patternLength: Int) -> Int {
        guard barWidth.isFinite, barWidth > 0, translationX.isFinite, patternLength > 0 else { return 0 }
        let grid = max(1, step), limit = Double(patternLength / grid + 1)
        let raw = translationX / barWidth * Double(barTicks) / Double(grid)
        return Int(min(limit, max(-limit, raw)).rounded())
    }

    /// The note a gesture would commit now. `lowPitch...highPitch` is the visible
    /// pitch window: a move never drags a note outside the rows the user sees.
    public static func preview(_ original: NoteEvent, operation: Operation, patternLength: Int,
                               translationX: Double, translationY: Double, barWidth: Double,
                               step: Int, rowHeight: Double = 24,
                               visiblePitches: ClosedRange<Int> = 0...127) -> NoteEvent {
        guard translationY.isFinite, rowHeight > 0 else { return original }
        let grid = max(1, step)
        let moves = steps(translationX: translationX, barWidth: barWidth, step: grid, patternLength: patternLength)
        let pitchDelta = Int(min(127, max(-127, translationY / rowHeight)).rounded())
        if moves == 0 && (operation == .resize || pitchDelta == 0) { return original }
        var temporary = Pattern(length: patternLength, notes: [original])
        switch operation {
        case .resize:
            NoteEditing.resize(original.id, in: &temporary, duration: original.duration + moves * grid, step: grid)
        case .move:
            let pitch = min(visiblePitches.upperBound, max(visiblePitches.lowerBound, original.pitch - pitchDelta))
            NoteEditing.move(original.id, in: &temporary, tick: original.tick + moves * grid, pitch: pitch, step: grid)
        }
        return temporary.notes?.first ?? original
    }

    public struct Point: Equatable, Sendable {
        public var x: Double, y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    /// Centre of the "End · beats" readout. It is placed above the finger when
    /// there is room and otherwise beside it (away from the finger), never
    /// below it, and always inside the content bounds.
    /// - finger: where the resize grip sits (the touch point).
    public static func readoutCenter(finger: Point, noteMinY: Double, readoutWidth: Double, readoutHeight: Double,
                                     contentWidth: Double, contentHeight: Double, clearance: Double = 34) -> Point {
        let halfW = readoutWidth / 2, halfH = readoutHeight / 2
        func clampX(_ x: Double) -> Double { min(max(halfW, x), max(halfW, contentWidth - halfW)) }
        func clampY(_ y: Double) -> Double { min(max(halfH, y), max(halfH, contentHeight - halfH)) }
        let aboveY = min(noteMinY, finger.y - clearance) - 8 - halfH
        if aboveY - halfH >= 0 { return Point(x: clampX(finger.x), y: aboveY) }
        // Top rows: put it level with the finger, on the side with more room.
        let leftX = finger.x - clearance - halfW, rightX = finger.x + clearance + halfW
        let x = leftX - halfW >= 0 ? leftX : (rightX + halfW <= contentWidth ? rightX : clampX(leftX))
        return Point(x: x, y: clampY(finger.y))
    }
}
