import MusicDomain
import SwiftUI

/// U11 · The tour card above the workspace: the step, what to do, "Show me" (goes there), "Next"
/// (passes over the step) and "Skip tour". A step ends when its real action happens.
struct DemoTourCard: View {
    @Bindable var session: Session
    let tour: DemoTour
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                if let step = tour.step {
                    Text(String(format: NSLocalizedString("STEP %lld OF %lld", comment: "Tour"), Int64(tour.number), Int64(DemoTour.count)))
                        .font(StudioTypography.index).foregroundStyle(Color.mint)
                        .accessibilityIdentifier("tour.number")
                    Spacer()
                    dots(current: step)
                    Button { withAnimation(reduceMotion ? nil : Luz.Motion.morph) { var next = tour; next.skip(); session.tour = next } } label: {
                        Image(systemName: "xmark").font(.footnote.weight(.semibold)).frame(width: 32, height: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(StudioQuietButtonStyle())
                    .accessibilityLabel("Skip tour")
                    .accessibilityIdentifier("tour.skip")
                } else {
                    Text("TOUR COMPLETE").font(StudioTypography.index).foregroundStyle(Color.mint)
                    Spacer()
                }
            }
            if let step = tour.step {
                Text(LocalizedStringKey(step.title)).font(.headline).accessibilityIdentifier("tour.title")
                Text(LocalizedStringKey(step.detail)).font(.subheadline).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button { show(step) } label: { Label("Show me", systemImage: "hand.point.up.left").frame(maxWidth: .infinity, minHeight: 40) }
                        .buttonStyle(StudioActionStyle(color: .mint))
                        .accessibilityIdentifier("tour.show")
                    Button { withAnimation(reduceMotion ? nil : Luz.Motion.morph) { var next = tour; next.next(); session.tour = next } } label: {
                        Text("Next").frame(minWidth: 72, minHeight: 40)
                    }
                    .buttonStyle(StudioActionStyle(color: .mint, prominent: false))
                    .accessibilityIdentifier("tour.next")
                }
            } else {
                Text(tour.passed.isEmpty ? "You've tried all five. Keep playing with the demo or start your own song in Projects." : "That's the tour. You can take it again any time in Settings → Show me around.")
                    .font(.subheadline).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                Button { withAnimation(reduceMotion ? nil : Luz.Motion.morph) { session.tour = nil } } label: { Text("Done").frame(maxWidth: .infinity, minHeight: 40) }
                    .buttonStyle(StudioActionStyle(color: .mint))
                    .accessibilityIdentifier("tour.finish")
            }
        }
        .padding(12)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous).strokeBorder(Color.mint.opacity(0.55), lineWidth: 1) }
        .padding(.horizontal, 8).padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tour.card")
        .accessibilityValue(Text(verbatim: tour.finished ? "finished" : "\(tour.number)/\(DemoTour.count)"))
    }

    private func dots(current: TourStep) -> some View {
        HStack(spacing: 4) {
            ForEach(TourStep.allCases, id: \.self) { step in
                Circle()
                    .fill(tour.done.contains(step) ? Color.mint : step == current ? Color.studioText : Color.outline)
                    .frame(width: 6, height: 6)
            }
        }.accessibilityHidden(true)
    }

    private func show(_ step: TourStep) {
        switch step {
        case .pads: session.tab = 1
        case .chords: session.tab = 0; session.pendingTourChord = true
        case .hum: session.presentEditor(.voice)
        case .layers: session.tab = 2
        case .export: session.finishTake(); session.exportTake = nil; session.sheet = .export
        }
        Luz.Haptics.selection()
    }
}
