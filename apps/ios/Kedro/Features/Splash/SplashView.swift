import SwiftUI

/// Launch splash (design §5.1): the full logo on night, a single fade/scale, 1.2 s max.
/// Always dark: the logo lives on a dark surface.
struct SplashView: View {
    @State private var isLogoVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.night
                .ignoresSafeArea()

            LogoView(width: 300)
                .scaleEffect(isLogoVisible || reduceMotion ? 1 : 0.92)
                .opacity(isLogoVisible ? 1 : 0)
        }
        .environment(\.colorScheme, .dark)
        .task {
            withAnimation(.smooth(duration: 0.6)) {
                isLogoVisible = true
            }
        }
    }
}

#Preview {
    SplashView()
}
