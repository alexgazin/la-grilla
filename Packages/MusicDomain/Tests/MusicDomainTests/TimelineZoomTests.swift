import Testing
@testable import MusicDomain

struct TimelineZoomTests {
    @Test func scrolledPinchesRetainTheMusicalPointUnderTheFinger() throws {
        // An already scrolled viewport is the counterexample to scaling only
        // the cells. Use many centers and scales, including fractional bars.
        for offset in [132.0, 281.75, 731.125] {
            for center in [44.0, 137.25, 302.0] {
                let pinch = try #require(TimelineZoom(barWidth: 120, offset: offset,
                    viewportWidth: 384, anchorX: center, barCount: 32))
                for scale in [0.8, 1.0, 1.35, 2.125, 4.0] {
                    let result = try #require(pinch.position(magnification: scale))
                    #expect(abs((result.offset + center) / result.barWidth - (offset + center) / 120) < 1e-10)
                }
            }
        }
    }

    @Test func clampingUsesTheNewContentBoundsAndNeverInventsBlankScrollSpace() throws {
        let right = try #require(TimelineZoom(barWidth: 300, offset: 2016,
            viewportWidth: 384, anchorX: 330, barCount: 8))
        let small = try #require(right.position(magnification: 0.01))
        #expect(small.barWidth == 68)
        #expect(small.offset == 8 * 68 - 384)
        let huge = try #require(right.position(magnification: 1000))
        #expect(huge.barWidth == 640)
        #expect(huge.offset >= 0 && huge.offset <= 8 * 640 - 384)

        let oneBar = try #require(TimelineZoom(barWidth: 384, offset: 90,
            viewportWidth: 844, anchorX: 700, barCount: 1))
        for scale in [0.001, 0.5, 1, 10] {
            let result = try #require(oneBar.position(magnification: scale))
            #expect(result.offset == 0)
            #expect(result.barWidth <= 640)
        }
    }

    @Test func subsequentPinchStartsFromTheSettledViewportAndRejectsInvalidInput() throws {
        let first = try #require(TimelineZoom(barWidth: 96, offset: 235,
            viewportWidth: 384, anchorX: 160, barCount: 16))
        let enlarged = try #require(first.position(magnification: 2.25))
        let next = try #require(TimelineZoom(barWidth: enlarged.barWidth, offset: enlarged.offset,
            viewportWidth: 384, anchorX: 290, barCount: 16))
        let reduced = try #require(next.position(magnification: 0.7))
        #expect(abs((reduced.offset + 290) / reduced.barWidth - (enlarged.offset + 290) / enlarged.barWidth) < 1e-10)
        #expect(first.position(magnification: .nan) == nil)
        #expect(first.position(magnification: .infinity) == nil)
        #expect(first.position(magnification: 0) == nil)
        #expect(TimelineZoom(barWidth: 0, offset: 0, viewportWidth: 384, anchorX: 0, barCount: 8) == nil)
        #expect(TimelineZoom(barWidth: 96, offset: .nan, viewportWidth: 384, anchorX: 0, barCount: 8) == nil)
        #expect(TimelineZoom(barWidth: 96, offset: 0, viewportWidth: 0, anchorX: 0, barCount: 8) == nil)
        #expect(TimelineZoom(barWidth: 96, offset: 0, viewportWidth: 384, anchorX: 0, barCount: 65) == nil)
    }
}
