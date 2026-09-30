import SwiftUI
import RENNDomain

/// Onboarding content scenes (02 D03, 03 M02) over the bundled demo clips (owner-approved).
/// Each plays its motion once and rests; none advances the page. Reduce Motion shows static
/// examples. Decorative: hidden from VoiceOver except the optional sound control.
struct OnboardingScene: View {
    let pageIndex: Int

    var body: some View {
        Group {
            switch pageIndex {
            case 0: CleanToLookScene()
            case 1: LookCardsScene()
            case 2: BeatScene()
            default: TapeShelfScene()
            }
        }
        .aspectRatio(4 / 5, contentMode: .fit)
        .frame(maxWidth: .infinity)
        // A new page starts a new scene; the old one stops its playback on disappear.
        .id(pageIndex)
    }
}

// MARK: Page 1: clean to one actual RENN Look

private struct CleanToLookScene: View {
    @Environment(\.showcase) private var showcase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var playback = DemoPlayback()
    @State private var look: LookDefinition?
    @State private var showsName = false

    private static let reveal = DemoReveal(delay: 1.0, duration: 1.4)

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let showcase, let look, !reduceMotion {
                DemoVideoView(
                    engine: showcase.engine, player: playback.player,
                    recipe: ShowcaseMedia.recipe(for: look), reveal: Self.reveal,
                    isActive: scenePhase == .active)
            } else if let look {
                LookPoster(look: look)
            }
            if let look {
                LookNameChip(look: look)
                    .padding(12)
                    .opacity(showsName || reduceMotion ? 1 : 0)
            }
        }
        .sceneFrame()
        .accessibilityHidden(true)
        .task {
            look = await showcase?.look(ShowcaseMedia.heroLookID)
            guard !reduceMotion, look != nil else { return }
            await playback.start(.street)
            try? await Task.sleep(for: .seconds(Self.reveal.delay + Self.reveal.duration))
            withAnimation(.easeOut(duration: 0.3)) { showsName = true }
        }
        .onChange(of: scenePhase) { _, phase in playback.setActive(phase == .active) }
        .onDisappear { playback.stop() }
    }
}

// MARK: Page 2: three treated versions; each card comes forward in turn

private struct LookCardsScene: View {
    @Environment(\.showcase) private var showcase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var looks: [LookDefinition] = []
    /// -1 while all three rest in the fan.
    @State private var selected = -1

    /// Left, right, then the centre card, which stays in front.
    private static let order = [0, 2, 1]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack {
                ForEach(Array(looks.enumerated()), id: \.element.id) { index, look in
                    let isSelected = index == selected
                    let side = CGFloat(index - 1)
                    LookCard(look: look, isSelected: isSelected)
                        .frame(width: width * 0.5)
                        .scaleEffect(isSelected ? 1 : 0.84)
                        .rotationEffect(.degrees(isSelected ? 0 : Double(side) * 7))
                        .offset(x: side * width * 0.26, y: isSelected ? -8 : 10)
                        .zIndex(isSelected ? 3 : (index == 1 ? 1 : 0))
                }
            }
            .frame(width: width, height: geometry.size.height)
        }
        .sceneFrame()
        .accessibilityHidden(true)
        .task {
            var loaded: [LookDefinition] = []
            for id in ShowcaseMedia.cardLookIDs {
                if let look = await showcase?.look(id) { loaded.append(look) }
            }
            looks = loaded
            guard loaded.count == 3 else { return }
            if reduceMotion {
                selected = 1
                return
            }
            for index in Self.order {
                try? await Task.sleep(for: .seconds(index == Self.order.first ? 0.5 : 0.9))
                guard !Task.isCancelled else { return }
                withAnimation(.spring(duration: 0.5, bounce: 0.15)) { selected = index }
            }
        }
    }
}

private struct LookCard: View {
    let look: LookDefinition
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LookPoster(look: look)
                .aspectRatio(3 / 4, contentMode: .fit)
            Text(LocalizedStringKey(look.nameKey))
                .font(RENNFont.roboto(13, medium: true, relativeTo: .footnote))
                .foregroundStyle(RENNColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .background(RENNColor.glassOpaqueFallback)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? RENNColor.brandYellow : Color.white.opacity(0.12), lineWidth: isSelected ? 2 : 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 6)
    }
}

// MARK: Page 3: the demo's own audio moves the picture

private struct BeatScene: View {
    @Environment(\.showcase) private var showcase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var playback = DemoPlayback()
    @State private var look: LookDefinition?
    @State private var timeline: BeatTimeline?

    var body: some View {
        ZStack(alignment: .bottom) {
            if let showcase, !reduceMotion {
                DemoVideoView(
                    engine: showcase.engine, player: playback.player,
                    recipe: ShowcaseMedia.recipe(for: look, beatIntensity: 0.9),
                    beatTimeline: timeline, isActive: scenePhase == .active)
                    .accessibilityHidden(true)
            } else if let look {
                LookPoster(look: look)
            }
            BeatMeter(timeline: timeline, player: playback.player, isAnimated: !reduceMotion)
                .frame(height: 34)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .accessibilityHidden(true)
        }
        .sceneFrame()
        .overlay(alignment: .topTrailing) {
            // Sound is opt-in and off by default; no microphone is involved (02 D03).
            if !reduceMotion {
                SoundToggle(isMuted: playback.isMuted) { playback.setMuted(!playback.isMuted) }
                    .padding(8)
            }
        }
        .task {
            look = await showcase?.look(ShowcaseMedia.beatLookID)
            guard !reduceMotion else { return }
            await playback.start(.dance)
            timeline = await showcase?.danceBeatTimeline()
        }
        .onChange(of: scenePhase) { _, phase in playback.setActive(phase == .active) }
        .onDisappear { playback.stop() }
    }
}

/// Energy bars from the demo audio's Beat timeline around the playhead, in brand colors.
private struct BeatMeter: View {
    let timeline: BeatTimeline?
    let player: PreviewPlayer
    let isAnimated: Bool

    private static let barCount = 28
    private static let spacing = 0.045

    var body: some View {
        TimelineView(.animation(paused: !isAnimated || timeline == nil)) { _ in
            let now = player.player.currentTime().seconds
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    Capsule()
                        .fill(RENNColor.brandSequence[index * 4 / Self.barCount])
                        .frame(maxWidth: .infinity)
                        .frame(height: max(3, 30 * level(at: now - Double(Self.barCount - 1 - index) * Self.spacing)))
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func level(at seconds: Double) -> Double {
        guard let timeline, seconds.isFinite, seconds >= 0,
              let time = try? RationalTime(value: Int64((seconds * 600).rounded()), timescale: 600),
              let frame = timeline.frame(at: time)
        else { return 0.08 }
        return min(1, Double(max(frame.energy, frame.onset)))
    }
}

private struct SoundToggle: View {
    let isMuted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RENNColor.textPrimary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.black.opacity(0.45)))
                .frame(width: RENNMetrics.minimumTouchTarget, height: RENNMetrics.minimumTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(isMuted ? LocalizedStringKey("onboarding.sound.turnOn") : LocalizedStringKey("onboarding.sound.turnOff")))
        .accessibilityIdentifier("onboarding.sound")
    }
}

// MARK: Page 4: the treated sample becomes a cassette and settles on the shelf

private struct TapeShelfScene: View {
    @Environment(\.showcase) private var showcase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var look: LookDefinition?
    /// 0 treated frame, 1 cassette cover, 2 settled on the shelf.
    @State private var stage = 0

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let caseWidth = width * 0.34
            let caseHeight = caseWidth * 1.5
            let shelfTop = height * 0.84
            let caseCenterY = stage == 2 ? shelfTop - caseHeight / 2 : height * 0.44
            // VHSCaseShell: 10 pt band, 8 pt inset, 3:4 print window.
            let window = CGSize(width: caseWidth - 16, height: (caseWidth - 16) * 4 / 3)
            let windowCenterY = caseCenterY - caseHeight / 2 + 18 + window.height / 2
            ZStack {
                ShelfPlank()
                    .frame(width: width - 32, height: 10)
                    .position(x: width / 2, y: shelfTop + 5)
                ForEach([-1, 1], id: \.self) { side in
                    // Empty slots, never fake tapes (02 D03).
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(RENNColor.textSecondary.opacity(0.3))
                        .frame(width: caseWidth * 0.9, height: caseHeight * 0.9)
                        .position(x: width / 2 + CGFloat(side) * caseWidth * 1.12, y: shelfTop - caseHeight * 0.45)
                        .opacity(stage == 2 ? 1 : 0)
                }
                if let look {
                    VHSCaseShell(
                        name: "", variant: 0, poster: showcase?.poster(for: look),
                        localizedName: LocalizedStringKey(look.nameKey))
                        .frame(width: caseWidth, height: caseHeight)
                        .position(x: width / 2, y: caseCenterY)
                        .opacity(stage == 0 ? 0 : 1)
                    LookPoster(look: look)
                        .frame(
                            width: stage == 0 ? width - 32 : window.width,
                            height: stage == 0 ? height * 0.7 : window.height)
                        .clipShape(RoundedRectangle(cornerRadius: stage == 0 ? 14 : 2, style: .continuous))
                        .position(x: width / 2, y: stage == 0 ? height * 0.42 : windowCenterY)
                        .opacity(stage == 0 ? 1 : 0)
                }
            }
        }
        .sceneFrame()
        .accessibilityHidden(true)
        .task {
            look = await showcase?.look(ShowcaseMedia.heroLookID)
            guard look != nil else { return }
            if reduceMotion {
                stage = 2
                return
            }
            try? await Task.sleep(for: .seconds(0.9))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.6)) { stage = 1 }
            try? await Task.sleep(for: .seconds(0.85))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.55, bounce: 0.2)) { stage = 2 }
        }
    }
}

/// A plain shelf plank shared by the onboarding and Home tape shelves.
struct ShelfPlank: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(hex: 0x6B5641), Color(hex: 0x3A2F24)],
                startPoint: .top, endPoint: .bottom))
            .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 3)
            .accessibilityHidden(true)
    }
}

private struct LookNameChip: View {
    let look: LookDefinition

    var body: some View {
        Text(LocalizedStringKey(look.nameKey))
            .font(RENNFont.roboto(13, medium: true, relativeTo: .footnote))
            .foregroundStyle(RENNColor.textPrimary)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(Capsule().fill(Color.black.opacity(0.45)))
    }
}

private extension View {
    func sceneFrame() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RENNColor.glassOpaqueFallback)
            .clipShape(RoundedRectangle(cornerRadius: RENNMetrics.panelRadius, style: .continuous))
    }
}
