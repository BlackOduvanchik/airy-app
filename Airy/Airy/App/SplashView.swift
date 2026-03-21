//
//  SplashView.swift
//  Airy
//
//  Animated splash screen shown during initial data load.
//

import SwiftUI

struct SplashView: View {
    @Environment(ThemeProvider.self) private var theme
    @State private var contentOpacity: Double = 0
    @State private var contentOffset: CGFloat = 10
    @State private var pulseScale: CGFloat = 1
    @State private var pulseOpacity: Double = 0.2
    @State private var barOffset: CGFloat = -0.4

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                OnboardingGradientBackground()

                // Glass orbs
                glassOrb(size: 300)
                    .position(x: -25, y: -25)

                glassOrb(size: 400)
                    .position(x: proxy.size.width + 40, y: proxy.size.height + 40)

                // Content
                VStack(spacing: 24) {
                    mascot
                    titleBlock
                    loadingBar
                }
                .opacity(contentOpacity)
                .offset(y: contentOffset)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 1.2)) {
                contentOpacity = 1
                contentOffset = 0
            }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                pulseScale = 1.2
                pulseOpacity = 0.4
            }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: false)) {
                barOffset = 1.0
            }
        }
    }

    // MARK: - Glass Orb

    private func glassOrb(size: CGFloat) -> some View {
        Circle()
            .fill(Color.white.opacity(0.15))
            .frame(width: size, height: size)
            .blur(radius: 20)
            .opacity(0.4)
    }

    // MARK: - Mascot

    private var mascot: some View {
        ZStack {
            // Pulsing glow ring
            Circle()
                .fill(Color.clear)
                .frame(width: 84, height: 84)
                .shadow(color: theme.accentBlue, radius: 30)
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)

            // Glass circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.9), Color.white.opacity(0.2)],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 50
                    )
                )
                .frame(width: 84, height: 84)
                .shadow(color: Color.white.opacity(0.8), radius: 2, x: 0, y: -1)
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 8)

            // Cloud icon
            Image(systemName: "cloud.fill")
                .font(.system(size: 36, weight: .thin))
                .foregroundColor(theme.textPrimary)
        }
    }

    // MARK: - Title

    private var titleBlock: some View {
        VStack(spacing: 8) {
            Text("AIRY")
                .font(.system(size: 32, weight: .light))
                .tracking(2)
                .foregroundColor(theme.textPrimary)

            Text(L("splash_tagline"))
                .font(.system(size: 14, weight: .medium))
                .tracking(0.5)
                .foregroundColor(theme.textSecondary)
                .opacity(0.8)
        }
        .padding(.top, 8)
    }

    // MARK: - Loading Bar

    private var loadingBar: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white.opacity(0.3))
            .frame(width: 140, height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    let width = geo.size.width
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.accentGreen)
                        .frame(width: width * 0.4)
                        .shadow(color: theme.accentGreen.opacity(0.4), radius: 8)
                        .offset(x: barOffset * width)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .padding(.top, 40)
    }
}
