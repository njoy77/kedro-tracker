import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Makes QR codes with Core Image (no UIKit).
nonisolated enum QRCode {
    /// A crisp QR code for `string`, `scale` pixels per module. nil if Core Image can't encode it.
    static func image(for string: String, scale: CGFloat = 12) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(output, from: output.extent)
    }
}

/// Invite with QR or AirDrop (design §5.6, §5.8): the rotating code for anyone in the room. It
/// opens Kedro if installed, or the App Clip if not; the same link goes by AirDrop. The token
/// changes every minute (J-12).
struct InviteQRSheet: View {
    let token: RotatingTableToken
    let tableWord: String
    let hostName: String

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    /// The table link's own code when there is one (its admission checks it), otherwise the
    /// lobby's rotating token (previews, no transport).
    private func inviteURL(at date: Date) -> URL {
        (app.discovery as? any TableInviting)?.inviteLink(for: token.gameID, at: date) ?? token.link(at: date).url
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: RotatingTableToken.period / 4)) { context in
                let url = inviteURL(at: context.date)
                ScrollView {
                    VStack(spacing: 18) {
                        Text(tableWord)
                            .kedroFont(.display)
                            .foregroundStyle(.cream)
                        Group {
                            if let image = QRCode.image(for: url.absoluteString) {
                                Image(decorative: image, scale: 1)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                            } else {
                                ContentUnavailableView("No Code", systemImage: "qrcode", description: Text("Use AirDrop instead."))
                            }
                        }
                        .padding(16)
                        .background(.white, in: .rect(cornerRadius: 20))
                        .frame(maxWidth: 300)
                        .accessibilityLabel("QR code to join \(hostName)'s table")

                        Text(app.voice.line("J-12"))
                            .font(.footnote)
                            .foregroundStyle(.silver)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        ShareLink(
                            item: url,
                            subject: Text("\(hostName)'s table"),
                            message: Text("Sit down at \(tableWord).")
                        ) {
                            Label("Send by AirDrop", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.kedroGlassWide)
                        .padding(.horizontal, 24)

                        Text("No app? The code opens the App Clip, and they can pick their guest seat.")
                            .font(.footnote)
                            .foregroundStyle(.silverDim)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(.night)
            .navigationTitle(Literal.text("button.inviteWithQR"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Literal.text("button.done")) { dismiss() }
                }
            }
        }
        .keepsScreenAwake(true)
    }
}

#Preview {
    InviteQRSheet(token: RotatingTableToken(gameID: PreviewData.sampleGameID), tableWord: "Cold Deck", hostName: "Noah")
        .previewEnvironment()
}
