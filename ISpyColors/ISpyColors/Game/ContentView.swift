//
//  ContentView.swift
//  ISpyColors
//
//  The single game screen. Built for a 5-year-old: huge shutter button, a giant
//  color circle + word, a star counter, and big friendly feedback. Layout uses
//  Spacers + maxWidth caps so it scales sensibly from iPhone to large iPad
//  instead of stretching controls across the screen.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var game = GameViewModel()

    /// Lifetime stars persist across launches (spec: @AppStorage).
    @AppStorage("lifetimeStars") private var lifetimeStars = 0

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
            // Cap content width so an iPad doesn't float tiny controls in a sea
            // of space; center it.
            let contentWidth = min(geo.size.width, 700)
            // Size the big elements to the available HEIGHT too — not just width —
            // so the whole column always fits and the shutter never spills off
            // the bottom on shorter screens. Caps keep them from getting huge on
            // iPad.
            let h = geo.size.height
            let circleSize = min(contentWidth * 0.50, h * 0.19, 300)
            let cameraHeight = min(contentWidth * 0.60, h * 0.21, 240)
            let shutterSize = min(contentWidth * 0.40, h * 0.16, 200)
            // Keep the shutter clear of the home indicator.
            let bottomInset = max(geo.safeAreaInsets.bottom, 16)

            ZStack {
                background

                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    Spacer(minLength: 8)

                    targetDisplay(circleSize: circleSize)

                    Spacer(minLength: 8)

                    cameraWindow(height: cameraHeight)
                        .frame(maxWidth: contentWidth)
                        .padding(.horizontal, 20)

                    Spacer(minLength: 12)

                    feedbackText

                    Spacer(minLength: 12)

                    shutterButton(size: shutterSize)
                        .padding(.bottom, bottomInset)
                }
                .frame(maxWidth: contentWidth)
                .frame(maxWidth: .infinity) // center the capped column

                if game.celebrate {
                    CelebrationOverlay()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
        .task {
            game.onAwardStar = { lifetimeStars += 1 }
            await game.camera.prepare()
            // Greet the first color out loud once the screen is up.
            game.announceColor()
        }
        .onChange(of: scenePhase) { _, phase in
            // Camera survives background/foreground cleanly.
            switch phase {
            case .active:   game.camera.start()
            case .background, .inactive: game.camera.stop()
            @unknown default: break
            }
        }
    }

    // MARK: Pieces

    private var background: some View {
        LinearGradient(colors: [Color(red: 0.62, green: 0.83, blue: 1.0),
                                Color(red: 0.85, green: 0.93, blue: 1.0)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            // Star counter.
            HStack(spacing: 8) {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
                Text("\(lifetimeStars)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.orange)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(.white, in: Capsule())
            .shadow(radius: 2, y: 1)

            Spacer()

            // New game.
            Button {
                withAnimation(.spring) { game.newGame() }
            } label: {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white, .orange)
                    .shadow(radius: 2, y: 1)
            }
            .accessibilityLabel("New game")
        }
    }

    private func targetDisplay(circleSize: CGFloat) -> some View {
        VStack(spacing: 10) {
            Text("I spy something")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.black.opacity(0.7))

            Text(game.targetColor.displayName)
                .font(.system(size: 52, weight: .black, design: .rounded))
                .foregroundStyle(game.targetColor == .white ? .black : game.targetColor.swatch)
                .shadow(color: .white.opacity(0.6), radius: 1)

            Circle()
                .fill(game.targetColor.swatch)
                .frame(width: circleSize, height: circleSize)
                .overlay(Circle().strokeBorder(.white, lineWidth: 8))
                .shadow(radius: 8, y: 4)
                .rotationEffect(.degrees(game.wiggle ? 4 : 0))
                .animation(.default.repeatCount(4, autoreverses: true).speed(3),
                           value: game.wiggle)
        }
    }

    private func cameraWindow(height: CGFloat) -> some View {
        ZStack {
            if game.camera.status == .authorized {
                CameraPreviewView(session: game.camera.session)
            } else if game.camera.status == .denied {
                cameraDenied
            } else {
                Color.black.opacity(0.15)
                ProgressView().tint(.white)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(.white, lineWidth: 6))
        .shadow(radius: 6, y: 3)
        .rotationEffect(.degrees(game.wiggle ? 1.5 : 0))
        .animation(.default.repeatCount(4, autoreverses: true).speed(3), value: game.wiggle)
    }

    private var cameraDenied: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.fill").font(.system(size: 40))
            Text("Please turn on the camera in Settings to play!")
                .multilineTextAlignment(.center)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .padding(.horizontal)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.4))
    }

    private var feedbackText: some View {
        Text(game.message)
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .multilineTextAlignment(.center)
            .foregroundStyle(feedbackColor)
            .padding(.horizontal, 24)
            .frame(minHeight: 52)
            .id(game.message) // re-trigger transition on change
            .transition(.scale.combined(with: .opacity))
            .animation(.spring, value: game.message)
    }

    private var feedbackColor: Color {
        switch game.lastOutcome {
        case .win: return .green
        case .duplicateFail: return .purple
        case .colorFail: return .red
        case .none: return .black.opacity(0.7)
        }
    }

    private func shutterButton(size: CGFloat) -> some View {
        Button {
            SoundEffects.shared.playShutter()
            Task { await game.takePhoto() }
        } label: {
            ZStack {
                Circle().fill(.white).shadow(radius: 6, y: 3)
                Circle().strokeBorder(.orange, lineWidth: 10).padding(8)
                Image(systemName: "camera.fill")
                    .font(.system(size: size * 0.34, weight: .bold))
                    .foregroundStyle(.orange)
                if game.isAnalyzing {
                    Circle().fill(.black.opacity(0.25))
                    ProgressView().tint(.white).scaleEffect(1.6)
                }
            }
            .frame(width: size, height: size)
        }
        .disabled(game.isAnalyzing || game.camera.status != .authorized)
        .scaleEffect(game.isAnalyzing ? 0.94 : 1)
        .animation(.spring, value: game.isAnalyzing)
        .accessibilityLabel("Take a picture")
    }
}

/// Confetti-ish burst of stars on a win.
private struct CelebrationOverlay: View {
    private let palette: [Color] = [.yellow, .orange, .pink, .green, .blue]

    var body: some View {
        ZStack {
            ForEach(0..<14, id: \.self) { i in
                Image(systemName: "star.fill")
                    .font(.system(size: CGFloat(20 + (i % 4) * 14)))
                    .foregroundStyle(palette[i % 5])
                    .offset(x: CGFloat((i * 53) % 280 - 140),
                            y: CGFloat((i * 97) % 360 - 180))
                    .opacity(0.9)
            }
            Text("⭐️")
                .font(.system(size: 140))
                .scaleEffect(1.0)
        }
        .transition(.scale)
    }
}

#Preview {
    ContentView()
}
