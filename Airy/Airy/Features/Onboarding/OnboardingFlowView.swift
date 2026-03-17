//
//  OnboardingFlowView.swift
//  Airy
//
//  6-page onboarding for new users. Pages 1–2 from design; 3–6 in same style.
//

import SwiftUI
import Combine

// MARK: - Design tokens (from HTML)

enum OnboardingDesign {
    static let bgTop = Color(red: 0.847, green: 0.882, blue: 0.902)
    static let bgBottomLeft = Color(red: 0.557, green: 0.729, blue: 0.647)
    static let bgBottomRight = Color(red: 0.886, green: 0.871, blue: 0.808)
    static let glowCenter = Color.white.opacity(0.8)

    static let textPrimary = Color(red: 0.118, green: 0.176, blue: 0.141)
    static let textSecondary = Color(red: 0.369, green: 0.478, blue: 0.420)
    static let textTertiary = Color(red: 0.541, green: 0.639, blue: 0.588)

    static let accentGreen = Color(red: 0.404, green: 0.627, blue: 0.510)
    static let accentBlue = Color(red: 0.482, green: 0.616, blue: 0.671)
    static let accentAmber = Color(red: 0.851, green: 0.627, blue: 0.357) // #D9A05B
    static let accentWarning = Color(red: 0.831, green: 0.639, blue: 0.451) // #D4A373
    static let textDanger = Color(red: 0.839, green: 0.478, blue: 0.478)   // #D67A7A

    static let glassBg = Color.white.opacity(0.45)
    static let glassBorder = Color.white.opacity(0.6)
    static let glassHighlight = Color.white.opacity(0.9)
    static let aiGlow = Color(red: 0.655, green: 0.545, blue: 0.980) // #A78BFA
}

// MARK: - Shared background

struct OnboardingGradientBackground: View {
    var body: some View {
        ZStack {
            OnboardingDesign.bgTop
            RadialGradient(
                gradient: Gradient(colors: [OnboardingDesign.bgTop, .clear]),
                center: UnitPoint(x: 0.2, y: -0.1),
                startRadius: 0,
                endRadius: 400
            )
            RadialGradient(
                gradient: Gradient(colors: [OnboardingDesign.bgBottomLeft, .clear]),
                center: UnitPoint(x: 0.1, y: 1.1),
                startRadius: 0,
                endRadius: 450
            )
            RadialGradient(
                gradient: Gradient(colors: [OnboardingDesign.bgBottomRight, .clear]),
                center: UnitPoint(x: 0.9, y: 1.1),
                startRadius: 0,
                endRadius: 400
            )
            RadialGradient(
                gradient: Gradient(colors: [OnboardingDesign.glowCenter, .clear]),
                center: UnitPoint(x: 0.5, y: 0.4),
                startRadius: 0,
                endRadius: 350
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Fade slide-in animation for page content

private struct FadeSlideInModifier: ViewModifier {
    @State private var opacity: Double = 0
    @State private var offset: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(y: offset)
            .onAppear {
                withAnimation(.easeOut(duration: 0.7).delay(0.2)) {
                    opacity = 1
                    offset = 0
                }
            }
    }
}

/// Fade slide-in that triggers when `isActive` becomes true (for TabView pages that preload).
private struct FadeSlideInWhenActiveModifier: ViewModifier {
    let isActive: Bool
    @State private var opacity: Double = 0
    @State private var offset: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(y: offset)
            .onChange(of: isActive) { _, active in
                if active {
                    withAnimation(.easeOut(duration: 0.7).delay(0.2)) {
                        opacity = 1
                        offset = 0
                    }
                } else {
                    opacity = 0
                    offset = 16
                }
            }
            .onAppear {
                if isActive {
                    withAnimation(.easeOut(duration: 0.7).delay(0.2)) {
                        opacity = 1
                        offset = 0
                    }
                }
            }
    }
}

private extension View {
    func fadeSlideIn() -> some View {
        modifier(FadeSlideInModifier())
    }

    func fadeSlideIn(whenActive isActive: Bool) -> some View {
        modifier(FadeSlideInWhenActiveModifier(isActive: isActive))
    }
}

// MARK: - Progress dots (6 dots, active index 0...5)
// Design: inactive 6pt, active 18pt width, text-primary / rgba(30,45,36,0.15)

struct OnboardingProgressDots: View {
    let currentPage: Int
    /// When true, active dot has stretching animation (page 0 only).
    var animateActiveDot: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? OnboardingDesign.textPrimary : OnboardingDesign.textPrimary.opacity(0.15))
                    .frame(width: dotWidth(for: index), height: 6)
            }
        }
        .frame(height: 24)
    }

    private func dotWidth(for index: Int) -> CGFloat {
        if index == currentPage {
            return animateActiveDot ? 36 : 18
        }
        return 6
    }
}

/// Progress dots with stretching animation on active (for page 0).
struct OnboardingProgressDotsAnimated: View {
    @State private var activeWidth: CGFloat = 18

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(OnboardingDesign.textPrimary)
                .frame(width: activeWidth, height: 6)
            ForEach(1..<6, id: \.self) { _ in
                Capsule()
                    .fill(OnboardingDesign.textPrimary.opacity(0.15))
                    .frame(width: 6, height: 6)
            }
        }
        .frame(height: 24)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                activeWidth = 40
            }
        }
        .onDisappear {
            activeWidth = 18
        }
    }
}

// MARK: - Page layout (content-shell + bottom-shell per design)

struct OnboardingPageLayout<Content: View, Bottom: View>: View {
    let content: Content
    let bottom: Bottom

    init(@ViewBuilder content: () -> Content, @ViewBuilder bottom: () -> Bottom) {
        self.content = content()
        self.bottom = bottom()
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)

                bottom
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40 + geo.safeAreaInsets.bottom)
            }
        }
    }
}

// MARK: - Flow container

struct OnboardingFlowView: View {
    var onFinish: () -> Void
    @State private var currentPage = 0

    var body: some View {
        ZStack {
            OnboardingGradientBackground()
            TabView(selection: $currentPage) {
                OnboardingWelcomePage(onNext: { currentPage = 1 }, onSkipToSignIn: onFinish)
                    .tag(0)
                OnboardingScreenshotsPage(onNext: { currentPage = 2 }, onSkip: { currentPage = 5 })
                    .tag(1)
                OnboardingSpendingPage(onNext: { currentPage = 3 }, onSkip: { currentPage = 5 }, isActive: currentPage == 2)
                    .tag(2)
                OnboardingSubscriptionsPage(onNext: { currentPage = 4 }, onSkip: { currentPage = 5 })
                    .tag(3)
                OnboardingMirrorPage(onNext: { currentPage = 5 }, onSkip: { currentPage = 5 })
                    .tag(4)
                OnboardingProOfferPage(onFinish: onFinish)
                    .tag(5)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.25), value: currentPage)
        }
    }
}

// MARK: - Page 1: Welcome

struct OnboardingWelcomePage: View {
    var onNext: () -> Void
    var onSkipToSignIn: () -> Void

    @State private var haloInnerScale: CGFloat = 1.0
    @State private var haloInnerOpacity: Double = 1.0
    @State private var haloMidScale: CGFloat = 1.0
    @State private var haloMidOpacity: Double = 1.0
    @State private var haloOuterScale: CGFloat = 1.0
    @State private var haloOuterOpacity: Double = 0.6
    @State private var mascotOffset: CGFloat = 0

    var body: some View {
        OnboardingPageLayout {
            VStack(spacing: 0) {
                topSection
                Text("Airy")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(2.6)
                    .textCase(.uppercase)
                    .foregroundColor(OnboardingDesign.textTertiary)
                    .padding(.bottom, 24)

                VStack(spacing: 8) {
                    Text("Your money,\nclearly understood.")
                        .font(.system(size: 38, weight: .light))
                        .tracking(-1)
                        .lineSpacing(2)
                        .multilineTextAlignment(.center)
                        .foregroundColor(OnboardingDesign.textPrimary)
                    Text("A calm, intelligent space for your finances.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(OnboardingDesign.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: 300)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: 400)
            .fadeSlideIn()
        } bottom: {
            VStack(spacing: 0) {
                OnboardingProgressDotsAnimated()
                    .padding(.bottom, 24)
                    .fadeSlideIn()

                VStack(spacing: 12) {
                    Button(action: onNext) {
                        Text("Get Started")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                    .background(OnboardingDesign.accentGreen)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                    .shadow(color: OnboardingDesign.accentGreen.opacity(0.2), radius: 12, x: 0, y: 8)
                    Button(action: onSkipToSignIn) {
                        Text("I already have an account")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(OnboardingDesign.textTertiary)
                            .frame(height: 44)
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                haloInnerScale = 1.05
                haloInnerOpacity = 0.4
            }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true).delay(0.5)) {
                haloMidScale = 1.05
                haloMidOpacity = 0.4
            }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true).delay(1.0)) {
                haloOuterScale = 1.12
                haloOuterOpacity = 0
            }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                mascotOffset = -6
            }
        }
    }

    private var topSection: some View {
        ZStack {
            Circle()
                .stroke(OnboardingDesign.accentBlue.opacity(0.05), lineWidth: 1)
                .frame(width: 200, height: 200)
                .scaleEffect(haloOuterScale)
                .opacity(haloOuterOpacity)
            Circle()
                .stroke(OnboardingDesign.accentBlue.opacity(0.1), lineWidth: 1)
                .frame(width: 140, height: 140)
                .scaleEffect(haloMidScale)
                .opacity(haloMidOpacity)
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                .frame(width: 100, height: 100)
                .scaleEffect(haloInnerScale)
                .opacity(haloInnerOpacity)
            mascotCircle
        }
        .frame(width: 200, height: 200)
        .padding(.bottom, 24)
    }

    private var mascotCircle: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.95), Color.white.opacity(0.3)],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 60
                    )
                )
                .frame(width: 96, height: 96)
                .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 8)
                .shadow(color: Color.white.opacity(0.8), radius: 2, x: 0, y: 2)
                .offset(y: mascotOffset)
            Image(systemName: "cloud")
                .font(.system(size: 48, weight: .regular))
                .foregroundColor(OnboardingDesign.textPrimary)
                .offset(y: mascotOffset)
        }
    }
}

// MARK: - Page 2: Screenshots

struct OnboardingScreenshotsPage: View {
    var onNext: () -> Void
    var onSkip: () -> Void

    var body: some View {
        OnboardingPageLayout {
            VStack(spacing: 0) {
                illustrationArea
                    .frame(maxWidth: .infinity)

                VStack(spacing: 8) {
                    Text("Screenshots become data.")
                        .font(.system(size: 38, weight: .light))
                        .tracking(-1)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundColor(OnboardingDesign.textPrimary)

                    Text("Point your camera at any receipt or bank statement. Airy reads it instantly.")
                        .font(.system(size: 15))
                        .foregroundColor(OnboardingDesign.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)

                    aiChip
                }
                .padding(.top, 32)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: 400)
            .fadeSlideIn()
        } bottom: {
            VStack(spacing: 0) {
                OnboardingProgressDots(currentPage: 1)
                    .padding(.bottom, 24)
                    .fadeSlideIn()

                VStack(spacing: 12) {
                    Button(action: onNext) {
                        Text("Continue")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                    .background(OnboardingDesign.accentGreen)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                    .shadow(color: OnboardingDesign.accentGreen.opacity(0.2), radius: 12, x: 0, y: 8)

                    Button(action: onSkip) {
                        Text("Skip")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(OnboardingDesign.textTertiary)
                            .frame(height: 44)
                    }
                }
            }
        }
    }

    private var illustrationArea: some View {
        ZStack(alignment: .bottom) {
            dottedArcPathView

            // Camera icon (bottom-left) — circle only, no square frame
            ZStack(alignment: .bottomLeading) {
                Color.clear
                    .frame(width: 300, height: 320)
                cameraIconView
                    .padding(.leading, 20)
                    .padding(.bottom, 20)
            }
            .frame(width: 300, height: 320)

            // Phone mockup
            VStack(spacing: 8) {
                screenshotThumb(line1: 0.7, line2: 0.4)
                screenshotThumb(line1: 0.8, line2: 0.5)
                screenshotThumb(line1: 0.65, line2: 0.3)
            }
            .padding(12)
            .frame(width: 140, height: 260)
            .background(.ultraThinMaterial)
            .overlay(OnboardingDesign.glassBg.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(OnboardingDesign.glassBorder, lineWidth: 1)
            )
            .shadow(color: OnboardingDesign.textPrimary.opacity(0.06), radius: 16, x: 0, y: 8)
        }
        .frame(width: 300, height: 320)
    }

    /// Uses TimelineView so animation continues smoothly when swiping back to this page (no onAppear reset).
    private var dottedArcPathView: some View {
        TimelineView(.animation(minimumInterval: 1.0/30)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let cycle = 20.0
            let t = (elapsed.truncatingRemainder(dividingBy: cycle)) / cycle
            let phase = t < 0.5 ? t * 400 : (1 - t) * 400
            Path { p in
                p.move(to: CGPoint(x: 42, y: 278))
                p.addCurve(
                    to: CGPoint(x: 200, y: 80),
                    control1: CGPoint(x: 80, y: 200),
                    control2: CGPoint(x: 120, y: 100)
                )
            }
            .trim(from: 0, to: 1)
            .stroke(
                OnboardingDesign.accentBlue.opacity(0.4),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [8, 8], dashPhase: phase)
            )
            .frame(width: 300, height: 320)
        }
    }

    private var cameraIconView: some View {
        ZStack {
            Circle()
                .fill(OnboardingDesign.glassBg)
                .overlay(Circle().stroke(OnboardingDesign.glassBorder, lineWidth: 1))
                .frame(width: 44, height: 44)

            Image(systemName: "camera.fill")
                .font(.system(size: 20))
                .foregroundColor(OnboardingDesign.textPrimary)
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }

    private func screenshotThumb(line1: CGFloat, line2: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(OnboardingDesign.textPrimary.opacity(0.1))
                .frame(height: 4)
                .frame(maxWidth: .infinity)
                .scaleEffect(x: line1, y: 1, anchor: .leading)
            RoundedRectangle(cornerRadius: 2)
                .fill(OnboardingDesign.textPrimary.opacity(0.1))
                .frame(height: 4)
                .frame(maxWidth: .infinity)
                .scaleEffect(x: line2, y: 1, anchor: .leading)
        }
        .padding(10)
        .frame(height: 50)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var aiChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
            Text("Powered by on-device AI")
                .font(.system(size: 13, weight: .bold))
        }
        .foregroundColor(OnboardingDesign.accentBlue)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(OnboardingDesign.glassBg)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(OnboardingDesign.glassBorder, lineWidth: 1))
        .shadow(color: OnboardingDesign.textPrimary.opacity(0.06), radius: 8, x: 0, y: 4)
        .padding(.top, 16)
    }
}

// MARK: - Page 3: See where it all goes (spending viz + insight chips)

struct OnboardingSpendingPage: View {
    var onNext: () -> Void
    var onSkip: () -> Void
    var isActive: Bool = true

    var body: some View {
        OnboardingPageLayout {
            VStack(spacing: 0) {
                Text("See where it\nall goes.")
                    .font(.system(size: 38, weight: .light))
                    .tracking(-1)
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(OnboardingDesign.textPrimary)
                    .padding(.bottom, 32)

                spendingGlassPanel
                    .padding(.bottom, 24)

                Text("AI reads your spending and explains it in plain language — no spreadsheets.")
                    .font(.system(size: 15))
                    .lineSpacing(2)
                    .foregroundColor(OnboardingDesign.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)

                Spacer(minLength: 0)
            }
            .padding(.top, 60)
            .frame(maxWidth: 400)
            .fadeSlideIn(whenActive: isActive)
        } bottom: {
            VStack(spacing: 0) {
                OnboardingProgressDots(currentPage: 2)
                    .padding(.bottom, 24)
                    .fadeSlideIn(whenActive: isActive)

                VStack(spacing: 12) {
                    Button(action: onNext) {
                        Text("Continue")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                    .background(OnboardingDesign.accentGreen)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                    .shadow(color: OnboardingDesign.accentGreen.opacity(0.2), radius: 12, x: 0, y: 8)

                    Button(action: onSkip) {
                        Text("Skip")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(OnboardingDesign.textTertiary)
                            .frame(height: 44)
                    }
                }
            }
        }
    }

    private var spendingGlassPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                vizBar
                vizLegend
            }

            VStack(alignment: .leading, spacing: 10) {
                insightChip(text: "You spent 12% less on dining this week")
                insightChip(text: "Your biggest category shift: Transport +$40")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .overlay(OnboardingDesign.glassBg.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(OnboardingDesign.glassBorder, lineWidth: 1)
        )
        .shadow(color: OnboardingDesign.textPrimary.opacity(0.06), radius: 16, x: 0, y: 8)
    }

    private var vizBar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(OnboardingDesign.accentGreen.opacity(0.8))
                    .frame(width: w * 0.45, height: 8)
                RoundedRectangle(cornerRadius: 4)
                    .fill(OnboardingDesign.accentBlue.opacity(0.8))
                    .frame(width: w * 0.30, height: 8)
                RoundedRectangle(cornerRadius: 4)
                    .fill(OnboardingDesign.bgBottomRight.opacity(0.8))
                    .frame(width: w * 0.25, height: 8)
            }
        }
        .frame(height: 8)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var vizLegend: some View {
        HStack(spacing: 12) {
            legendItem(color: OnboardingDesign.accentGreen, label: "Food")
            legendItem(color: OnboardingDesign.accentBlue, label: "Transport")
            legendItem(color: OnboardingDesign.bgBottomRight, label: "Other")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, -8)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .foregroundColor(OnboardingDesign.textTertiary)
        }
    }

    private func insightChip(text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 18))
                .foregroundColor(OnboardingDesign.accentBlue)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(OnboardingDesign.textPrimary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.25))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Page 4: Never pay twice (subscription cards stack)

struct OnboardingSubscriptionsPage: View {
    var onNext: () -> Void
    var onSkip: () -> Void

    private let cardMaxWidth: CGFloat = 310

    @State private var card1Offset: CGFloat = 0
    @State private var card2Offset: CGFloat = 20
    @State private var card3Offset: CGFloat = 40
    @State private var badgeScale: CGFloat = 1
    @State private var badgeOpacity: Double = 1

    var body: some View {
        OnboardingPageLayout {
            VStack(spacing: 0) {
                illustrationStack
                    .frame(height: 320)

                contentArea
                    .padding(.top, 24)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: 400)
            .fadeSlideIn()
        } bottom: {
            VStack(spacing: 0) {
                OnboardingProgressDots(currentPage: 3)
                    .padding(.bottom, 24)
                    .fadeSlideIn()

                VStack(spacing: 12) {
                    Button(action: onNext) {
                        Text("Continue")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                    .background(OnboardingDesign.accentGreen)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                    .shadow(color: OnboardingDesign.accentGreen.opacity(0.2), radius: 12, x: 0, y: 8)

                    Button(action: onSkip) {
                        Text("Skip")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(OnboardingDesign.textTertiary)
                            .frame(height: 44)
                    }
                }
            }
        }
    }

    private var contentArea: some View {
        VStack(spacing: 0) {
            Text("Never pay twice.")
                .font(.system(size: 38, weight: .light))
                .tracking(-1)
                .foregroundColor(OnboardingDesign.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)

            Text("Airy finds duplicate charges, forgotten trials, and quietly expensive subscriptions.")
                .font(.system(size: 15))
                .lineSpacing(1.5)
                .foregroundColor(OnboardingDesign.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .padding(.horizontal, 10)
        .padding(.top, 24)
    }

    private var illustrationStack: some View {
        ZStack {
            // Card 3 (back) — Adobe CC, green tint
            subRowCard(
                iconColor: Color(red: 1, green: 0, blue: 0),
                iconName: "doc.fill",
                name: "Adobe CC",
                pill: "Monthly",
                price: "$52.99",
                badge: nil,
                badgeBottom: false,
                cardBackground: OnboardingDesign.accentGreen.opacity(0.15)
            )
            .scaleEffect(0.92)
            .offset(y: card3Offset)
            .opacity(0.8)
            .zIndex(1)

            // Card 2 (middle) — Spotify, default glass
            subRowCard(
                iconColor: Color(red: 0.114, green: 0.725, blue: 0.329),
                iconName: "music.note",
                name: "Spotify",
                pill: "Individual",
                price: "$10.99",
                badge: "Trial ending in 2 days",
                badgeBottom: true,
                cardBackground: nil,
                badgeScale: badgeScale,
                badgeOpacity: badgeOpacity
            )
            .scaleEffect(0.96)
            .offset(y: card2Offset)
            .opacity(0.95)
            .zIndex(2)

            // Card 1 (front) — Netflix, amber tint
            subRowCard(
                iconColor: Color(red: 0.898, green: 0.035, blue: 0.078),
                iconName: "play.rectangle.fill",
                name: "Netflix",
                pill: "Family Plan",
                price: "$19.99",
                badge: "Duplicate detected",
                badgeBottom: false,
                cardBackground: OnboardingDesign.accentAmber.opacity(0.12),
                badgeScale: badgeScale,
                badgeOpacity: badgeOpacity
            )
            .scaleEffect(1)
            .offset(y: card1Offset)
            .zIndex(3)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                card1Offset = -6
            }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true).delay(0.4)) {
                card2Offset = 14
            }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true).delay(0.8)) {
                card3Offset = 34
            }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                badgeScale = 0.97
                badgeOpacity = 0.75
            }
        }
    }

    private func subRowCard(
        iconColor: Color,
        iconName: String,
        name: String,
        pill: String,
        price: String,
        badge: String?,
        badgeBottom: Bool,
        cardBackground: Color? = nil,
        badgeScale: CGFloat = 1,
        badgeOpacity: Double = 1
    ) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14)
                .fill(iconColor)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: iconName)
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                )
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(OnboardingDesign.textPrimary)
                Text(pill)
                    .font(.system(size: 10, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundColor(OnboardingDesign.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(price)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(OnboardingDesign.textPrimary)
        }
        .padding(16)
        .frame(maxWidth: cardMaxWidth)
        .background(cardBackground ?? OnboardingDesign.glassBg)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(OnboardingDesign.glassBorder, lineWidth: 1)
        )
        .shadow(color: OnboardingDesign.textPrimary.opacity(0.06), radius: 16, x: 0, y: 8)
        .overlay(alignment: .topTrailing) {
            if let badge = badge, !badgeBottom {
                badgeLabel(badge)
                    .scaleEffect(badgeScale)
                    .opacity(badgeOpacity)
                    .offset(x: 12, y: -10)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let badge = badge, badgeBottom {
                badgeLabel(badge)
                    .scaleEffect(badgeScale)
                    .opacity(badgeOpacity)
                    .offset(x: 12, y: 8)
            }
        }
    }

    private func badgeLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(OnboardingDesign.accentAmber)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: OnboardingDesign.accentAmber.opacity(0.3), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Page 5: Your money has patterns (Money Mirror)

struct OnboardingMirrorPage: View {
    var onNext: () -> Void
    var onSkip: () -> Void

    var body: some View {
        OnboardingPageLayout {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("Your money has patterns.")
                        .font(.system(size: 38, weight: .light))
                        .tracking(-1)
                        .lineSpacing(2)
                        .multilineTextAlignment(.center)
                        .foregroundColor(OnboardingDesign.textPrimary)

                    Text("Money Mirror reflects your habits back to you — gently, honestly, and clearly.")
                        .font(.system(size: 15))
                        .lineSpacing(1.5)
                        .foregroundColor(OnboardingDesign.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                .padding(.bottom, 24)

                mirrorGlassPanel
                    .padding(.horizontal, 20)

                Spacer(minLength: 0)
            }
            .padding(.top, 60)
            .frame(maxWidth: 400)
            .fadeSlideIn()
        } bottom: {
            VStack(spacing: 0) {
                OnboardingProgressDots(currentPage: 4)
                    .padding(.bottom, 24)
                    .fadeSlideIn()

                VStack(spacing: 12) {
                    Button(action: onNext) {
                        Text("Continue")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                    .background(OnboardingDesign.accentGreen)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                    .shadow(color: OnboardingDesign.accentGreen.opacity(0.2), radius: 12, x: 0, y: 8)

                    Button(action: onSkip) {
                        Text("Skip for now")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(OnboardingDesign.textSecondary)
                            .frame(height: 44)
                    }
                }
            }
        }
    }

    private var mirrorGlassPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("MONEY MIRROR")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(OnboardingDesign.textTertiary)
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 20))
                    .foregroundColor(OnboardingDesign.accentBlue)
            }

            VStack(spacing: 12) {
                insightRow(accentColor: OnboardingDesign.accentGreen, emoji: "🗓️", text: "You tend to overspend on Fridays")
                insightRow(accentColor: OnboardingDesign.accentAmber, emoji: "📈", text: "Subscriptions grew 18% this quarter")
                insightRow(accentColor: OnboardingDesign.accentGreen, emoji: "🥗", text: "Your food budget has been consistent for 3 months ✓")
            }

            sparklineView
                .frame(height: 60)
                .padding(.top, 10)
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .overlay(OnboardingDesign.glassBg.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(OnboardingDesign.glassBorder, lineWidth: 1)
        )
        .shadow(color: OnboardingDesign.textPrimary.opacity(0.06), radius: 16, x: 0, y: 8)
    }

    private func insightRow(accentColor: Color, emoji: String, text: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(emoji)
                .font(.system(size: 18))

            Text(text)
                .font(.system(size: 14))
                .lineSpacing(2)
                .foregroundColor(OnboardingDesign.textPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .fill(accentColor)
                .frame(width: 4)
                .frame(maxHeight: .infinity),
            alignment: .leading
        )
    }

    private var sparklineView: some View {
        GeometryReader { geo in
            sparklinePaths(width: geo.size.width, height: geo.size.height)
        }
    }

    private func sparklinePaths(width w: CGFloat, height h: CGFloat) -> some View {
        let sx = w / 300
        let sy = h / 60
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * sx, y: y * sy)
        }
        return ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: pt(0, 50))
                p.addQuadCurve(to: pt(100, 45), control: pt(50, 20))
                p.addQuadCurve(to: pt(200, 15), control: pt(150, 70))
                p.addQuadCurve(to: pt(300, 40), control: pt(250, -40))
                p.addLine(to: pt(300, 60))
                p.addLine(to: pt(0, 60))
                p.closeSubpath()
            }
            .fill(OnboardingDesign.accentGreen.opacity(0.05))

            Path { p in
                p.move(to: pt(0, 50))
                p.addQuadCurve(to: pt(100, 45), control: pt(50, 20))
                p.addQuadCurve(to: pt(200, 15), control: pt(150, 70))
                p.addQuadCurve(to: pt(300, 40), control: pt(250, -40))
            }
            .stroke(OnboardingDesign.accentGreen, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }
}

struct OnboardingGenericPage: View {
    let title: String
    let subtitle: String
    let pageIndex: Int
    var onNext: () -> Void
    var onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgressDots(currentPage: pageIndex)
                .padding(.top, 60)

            VStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 38, weight: .light))
                    .tracking(-1)
                    .multilineTextAlignment(.center)
                    .foregroundColor(OnboardingDesign.textPrimary)

                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundColor(OnboardingDesign.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            .padding(.horizontal, 40)
            .padding(.top, 80)

            Spacer(minLength: 24)

            VStack(spacing: 20) {
                Button(action: onNext) {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(OnboardingDesign.textPrimary)
                        .frame(width: 310, height: 60)
                }
                .background(.ultraThinMaterial)
                .overlay(OnboardingDesign.glassBg.opacity(0.6))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(OnboardingDesign.glassBorder, lineWidth: 1)
                )
                .shadow(color: OnboardingDesign.textPrimary.opacity(0.06), radius: 16, x: 0, y: 8)

                Button(action: onSkip) {
                    Text("Skip")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(OnboardingDesign.textTertiary)
                }
            }
            .padding(.bottom, 50)
        }
    }
}

// MARK: - Page 6: Airy Pro offer (subscribe / trial / maybe later)

private let deviceIdKey = "airy_device_id"

struct OnboardingProOfferPage: View {
    @Environment(AuthStore.self) private var authStore
    var onFinish: () -> Void

    enum Plan: String, CaseIterable {
        case monthly
        case yearly
    }

    @State private var selectedPlan: Plan = .yearly
    @State private var products: [StoreKitProductInfo] = []
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var errorMessage: String?

    var body: some View {
        OnboardingPageLayout {
            VStack(spacing: 0) {
                headerSection
                    .padding(.bottom, 16)

                featuresCard
                    .padding(.bottom, 16)

                pricingToggle
                    .padding(.bottom, 12)

                Text("No charge today · Cancel anytime")
                    .font(.system(size: 13))
                    .foregroundColor(OnboardingDesign.textTertiary)
                    .padding(.bottom, 4)

                if let err = errorMessage {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 4)
                }

                HStack(spacing: 40) {
                    Button("Restore Purchase") { Task { await restore() } }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(OnboardingDesign.textTertiary)
                        .disabled(isRestoring)
                }
                .padding(.bottom, 16)

                Spacer(minLength: 0)
            }
            .padding(.top, 24)
            .frame(maxWidth: 400)
            .fadeSlideIn()
        } bottom: {
            VStack(spacing: 0) {
                OnboardingProgressDots(currentPage: 5)
                    .padding(.bottom, 24)
                    .fadeSlideIn()

                VStack(spacing: 12) {
                    Button {
                        Task { await startTrialOrSubscribe() }
                    } label: {
                        Text("Start Free 7-Day Trial")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                    .background(OnboardingDesign.accentGreen)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
                    .shadow(color: OnboardingDesign.accentGreen.opacity(0.2), radius: 12, x: 0, y: 8)
                    .disabled(isPurchasing)
                    .overlay {
                        if isPurchasing {
                            ProgressView()
                                .tint(.white)
                        }
                    }

                    Button("Maybe later") { onFinish() }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(OnboardingDesign.textTertiary)
                        .frame(height: 44)
                }
            }
        }
        .task { await loadProducts() }
        .onReceive(NotificationCenter.default.publisher(for: .airyEntitlementsDidChange)) { _ in
            onFinish()
        }
    }

    private var headerSection: some View {
        VStack(spacing: 0) {
            Text("Think clearly\nabout money.")
                .font(.system(size: 40, weight: .light))
                .tracking(-1)
                .lineSpacing(2)
                .multilineTextAlignment(.center)
                .foregroundColor(OnboardingDesign.textPrimary)
                .padding(.bottom, 8)

            Text("Unlock everything Airy has to offer.")
                .font(.system(size: 15))
                .foregroundColor(OnboardingDesign.textSecondary)
        }
    }

    private var featuresCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            proFeatureRow(
                iconBg: OnboardingDesign.accentGreen.opacity(0.15),
                iconName: "calendar",
                name: "Unlimited Screenshot Analysis",
                benefit: "Import data just by snapping photos"
            )
            proFeatureRow(
                iconBg: OnboardingDesign.accentBlue.opacity(0.15),
                iconName: "sparkles",
                name: "AI Money Mirror",
                benefit: "Daily reflections on your spending"
            )
            proFeatureRow(
                iconBg: OnboardingDesign.accentAmber.opacity(0.15),
                iconName: "arrow.down.circle",
                name: "Subscription Tracker",
                benefit: "Never pay for a ghost sub again"
            )
            proFeatureRow(
                iconBg: Color.teal.opacity(0.15),
                iconName: "chart.bar",
                name: "Advanced Analytics",
                benefit: "Deep trends and forecasting"
            )
            proFeatureRow(
                iconBg: OnboardingDesign.textTertiary.opacity(0.15),
                iconName: "clock",
                name: "Yearly Review",
                benefit: "Comprehensive annual net worth recap"
            )
            proFeatureRow(
                iconBg: Color.purple.opacity(0.15),
                iconName: "cloud",
                name: "Cloud Sync",
                benefit: "Secure backup across all devices"
            )
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .overlay(OnboardingDesign.glassBg.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(OnboardingDesign.glassBorder, lineWidth: 1)
        )
        .shadow(color: OnboardingDesign.textPrimary.opacity(0.06), radius: 16, x: 0, y: 8)
    }

    private func proFeatureRow(iconBg: Color, iconName: String, name: String, benefit: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(iconBg)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: iconName)
                        .font(.system(size: 14))
                        .foregroundColor(OnboardingDesign.textPrimary)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(OnboardingDesign.textPrimary)
                Text(benefit)
                    .font(.system(size: 11))
                    .foregroundColor(OnboardingDesign.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(OnboardingDesign.accentGreen)
        }
    }

    private var pricingToggle: some View {
        VStack(spacing: 10) {
            planOption(plan: .monthly, label: "Monthly", price: monthlyPrice, productId: StoreKitService.productId)
            planOption(plan: .yearly, label: "Yearly", price: yearlyPrice, badge: "SAVE 40%", productId: StoreKitService.productIdYearly)
        }
    }

    private func planOption(plan: Plan, label: String, price: String, badge: String? = nil, productId: String) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            withAnimation(.easeOut(duration: 0.2)) {
                selectedPlan = plan
            }
            Task { await purchase(productId: productId) }
        } label: {
            HStack {
                HStack(spacing: 8) {
                    Text(label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(OnboardingDesign.textPrimary)
                    if let badge = badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(OnboardingDesign.accentAmber)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                Spacer()
                Text(price)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(OnboardingDesign.textPrimary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.white.opacity(0.6) : Color.white.opacity(0.3))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isSelected ? OnboardingDesign.accentGreen : Color.white.opacity(0.5), lineWidth: isSelected ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: isSelected ? OnboardingDesign.accentGreen.opacity(0.2) : .clear, radius: 15, x: 0, y: 0)
        .disabled(isPurchasing)
    }

    private var monthlyPrice: String {
        products.first(where: { $0.id == StoreKitService.productId })?.displayPrice ?? "$6.99"
    }

    private var yearlyPrice: String {
        products.first(where: { $0.id == StoreKitService.productIdYearly })?.displayPrice ?? "$49.99"
    }

    private func loadProducts() async {
        guard #available(iOS 15.0, *) else { return }
        do {
            let list = try await StoreKitService.shared.loadAllProProducts()
            await MainActor.run {
                products = list.map { StoreKitProductInfo(id: $0.id, displayPrice: String(describing: $0.displayPrice)) }
            }
        } catch {
            await MainActor.run {
                products = []
            }
        }
    }

    /// Start Free Trial: 7 days free, then monthly subscription ($6.99/mo).
    private func startTrialOrSubscribe() async {
        await purchase(productId: StoreKitService.productId)
    }

    private func purchase(productId: String) async {
        guard #available(iOS 15.0, *) else { onFinish(); return }
        isPurchasing = true
        errorMessage = nil
        defer { Task { @MainActor in isPurchasing = false } }
        do {
            let list = try await StoreKitService.shared.loadAllProProducts()
            guard let product = list.first(where: { $0.id == productId }) else {
                await MainActor.run { errorMessage = "Product not available" }
                return
            }
            guard let transaction = try await StoreKitService.shared.purchase(product) else {
                return
            }
            performAutoLogin(transactionId: String(transaction.id))
            await MainActor.run { onFinish() }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func restore() async {
        guard #available(iOS 15.0, *) else { return }
        isRestoring = true
        errorMessage = nil
        defer { Task { @MainActor in isRestoring = false } }
        do {
            let txId = try await StoreKitService.shared.restore()
            if let id = txId {
                performAutoLogin(transactionId: id)
            }
            await MainActor.run { onFinish() }
        } catch StoreKitError.noPurchasesFound {
            await MainActor.run { errorMessage = (StoreKitError.noPurchasesFound as LocalizedError).errorDescription }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    /// Local-only: after purchase, create session so user enters app. No backend.
    private func performAutoLogin(transactionId: String) {
        let id = "storekit-\(transactionId)"
        authStore.setAuth(userIdentifier: id)
    }
}

private struct StoreKitProductInfo: Identifiable {
    let id: String
    let displayPrice: String
}

#Preview("Onboarding flow") {
    OnboardingFlowView(onFinish: {})
}

#Preview("Welcome page") {
    ZStack {
        OnboardingGradientBackground()
        OnboardingWelcomePage(onNext: {}, onSkipToSignIn: {})
    }
}

#Preview("Screenshots page") {
    ZStack {
        OnboardingGradientBackground()
        OnboardingScreenshotsPage(onNext: {}, onSkip: {})
    }
}

#Preview("Spending page") {
    ZStack {
        OnboardingGradientBackground()
        OnboardingSpendingPage(onNext: {}, onSkip: {})
    }
}

#Preview("Subscriptions page") {
    ZStack {
        OnboardingGradientBackground()
        OnboardingSubscriptionsPage(onNext: {}, onSkip: {})
    }
}

#Preview("Mirror page") {
    ZStack {
        OnboardingGradientBackground()
        OnboardingMirrorPage(onNext: {}, onSkip: {})
    }
}

#Preview("Pro offer page") {
    ZStack {
        OnboardingGradientBackground()
        OnboardingProOfferPage(onFinish: {})
    }
    .environment(AuthStore())
}
