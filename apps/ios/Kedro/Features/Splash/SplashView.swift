import SwiftUI

struct SplashView: View {
    @State private var isLogoVisible = false

    var body: some View {
        ZStack {
            Color.brandBackground
                .ignoresSafeArea()

            Image(.logo)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300)
                .scaleEffect(isLogoVisible ? 1 : 0.92)
                .opacity(isLogoVisible ? 1 : 0)
                .accessibilityLabel("Kedro")
        }
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
