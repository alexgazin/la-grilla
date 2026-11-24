import SwiftUI
import MusicDomain

/// 54 · Share the song as a link others open with "Make your version". The music rides inside the
/// link; recorded and imported sounds stay in the project file.
struct RemixShareSection: View {
    @Bindable var session: Session
    @AppStorage("remix.author") private var author = ""
    private var allowed: Bool { RemixLink.allowsRemix(session.project.license) }
    private var link: Result<URL, Error> { Result { try session.remixLink(author: author) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SmallHeading(text: "REMIX LINK")
            if let credit = session.project.remixOf {
                Text(credit.author.map { String(format: NSLocalizedString("Your version of “%@” by %@", comment: "Remix credit"), credit.title, $0) }
                     ?? String(format: NSLocalizedString("Your version of “%@”", comment: "Remix credit"), credit.title))
                    .font(.caption).foregroundStyle(Color.muted).accessibilityIdentifier("remix.credit")
            }
            if !allowed {
                Text("Choose how others may use the song. A link lets them open it and make their version, with your name on it.")
                    .font(.caption).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    licenceButton(.attribution, title: "Remix with credit", identifier: "remix.allow")
                    licenceButton(.nonCommercial, title: "Not for sale", identifier: "remix.allow-nc")
                }
            } else {
                TextField("Your name on the remix (optional)", text: $author).textInputAutocapitalization(.words)
                    .accessibilityIdentifier("remix.author")
                switch link {
                case .success(let url):
                    ShareLink(item: url, subject: Text(session.project.name), message: Text("Make your version in La Grilla. If the link does not open, copy it and tap Paste in La Grilla › Projects.")) {
                        Label("Share remix link", systemImage: "link").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(StudioActionStyle()).accessibilityIdentifier("remix.share")
                    Text("Notes, chords, beat and mix go in the link; it opens La Grilla directly, nothing is uploaded. Recorded and imported sounds travel only in the project file.")
                        .font(.caption).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                case .failure(let error):
                    Text(error.localizedDescription).font(.caption).foregroundStyle(Color.record).accessibilityIdentifier("remix.error")
                }
            }
        }
        .padding(14)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
    }

    private func licenceButton(_ licence: SongLicense, title: LocalizedStringKey, identifier: String) -> some View {
        Button { session.edit { $0.license = licence.rawValue } } label: {
            Text(title).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(StudioQuietButtonStyle()).accessibilityIdentifier(identifier)
    }
}

/// 54 · This week's challenge with its rules ticked against the open song, and a clip to post.
struct WeeklyChallengeCard: View {
    @Bindable var session: Session
    private var challenge: WeeklyChallenge { WeeklyChallenge.current() }

    var body: some View {
        let checks = challenge.check(session.project)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Challenge of the week", systemImage: "flag.checkered").font(.caption.weight(.semibold)).foregroundStyle(Color.mint)
                Spacer()
                Text(verbatim: challenge.tag).font(.caption.monospaced()).foregroundStyle(Color.muted).textSelection(.enabled)
            }
            Text(LocalizedStringKey(challenge.title)).font(.headline)
            Text(LocalizedStringKey(challenge.idea)).font(.caption).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(checks.enumerated()), id: \.offset) { index, check in
                Label(check.rule.title, systemImage: check.met ? "checkmark.circle.fill" : "circle")
                    .font(.callout).foregroundStyle(check.met ? Color.mint : Color.studioText)
                    .accessibilityValue(Text(check.met ? "Done" : "Not yet"))
                    .accessibilityIdentifier("challenge.rule.\(index)")
            }
            if checks.allSatisfy(\.met) {
                Button {
                    session.exportPreset = Session.ExportFormat.video.rawValue
                    session.exportClip = .medium
                    session.sheet = .export
                } label: { Label("Post my entry", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(StudioActionStyle()).accessibilityIdentifier("challenge.post")
            } else {
                Text(String(format: NSLocalizedString("Checked against “%@”.", comment: "Challenge"), session.project.name))
                    .font(.caption2).foregroundStyle(Color.muted)
            }
        }
        .padding(14)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: Luz.Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("challenge.card")
    }
}
