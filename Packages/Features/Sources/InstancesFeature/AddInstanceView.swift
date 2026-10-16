import SwiftUI
import CoreImage.CIFilterBuiltins
import Core
import DesignSystem

struct AddInstanceView: View {
    @Bindable var model: AddInstanceModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            switch model.step {
            case .enterURL, .detecting:
                Section {
                    TextField(text: $model.urlText, prompt: Text(verbatim: "pipedapi.example.com")) {
                        Text("Address")
                    }
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .onSubmit { Task { await model.submit() } }
                    .accessibilityIdentifier("instance.url")
                } footer: {
                    if let error = model.error {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text("The app works out whether it's Piped, Invidious or YT Zero.")
                    }
                }
            case .pairing(let code):
                PairingSection(code: code, open: { openURL($0) })
            case .done:
                Section {
                    Label { Text("Instance added") } icon: { Image(systemName: "checkmark.circle.fill") }
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle(Text("Add Instance"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { model.cancelPairing(); dismiss() } label: { Text("Cancel") }
            }
            ToolbarItem(placement: .confirmationAction) {
                switch model.step {
                case .enterURL:
                    Button { Task { await model.submit() } } label: { Text("Next") }
                        .disabled(model.urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                case .detecting:
                    ProgressView()
                case .pairing:
                    EmptyView()
                case .done:
                    Button { dismiss() } label: { Text("Done") }
                }
            }
        }
    }
}

/// YT Zero sign-in: approve this device from a browser where you're signed in to YT Zero.
private struct PairingSection: View {
    let code: YTZeroDeviceAuth.Code
    let open: (URL) -> Void

    var body: some View {
        Section {
            VStack(spacing: Tokens.Spacing.l) {
                Text(code.userCode)
                    .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("pairing.code")
                if let image = Self.qrCode(for: code.verificationURLComplete ?? code.verificationURL) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 180, height: 180)
                        .accessibilityLabel(Text("QR code for the pairing page"))
                }
                ProgressView { Text("Waiting for approval…") }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Tokens.Spacing.l)
            Button { open(code.verificationURLComplete ?? code.verificationURL) } label: {
                Text("Open Pairing Page")
            }
        } header: {
            Text("Pair with YT Zero")
        } footer: {
            Text("Open \(code.verificationURL.absoluteString) where you're signed in to YT Zero and enter this code, or scan it with another device.")
        }
    }

    private static func qrCode(for url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
