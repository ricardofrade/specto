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
                        Text("The app works out whether it's Piped, Invidious, YT Zero or PeerTube.")
                    }
                }
                PublicServersSection(model: model)
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
        .inlineNavigationTitle()
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
                    .selectableText()
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

/// No server of your own: public PeerTube servers from joinpeertube.org's index. Each hosts
/// its own videos; tapping one adds it like a typed address.
private struct PublicServersSection: View {
    @Bindable var model: AddInstanceModel

    var body: some View {
        Section {
            HStack {
                TextField(text: $model.serverSearch, prompt: Text("Search servers")) { Text("Search servers") }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("publicServers.search")
                Picker(selection: $model.serverSort) {
                    Text("Most videos").tag(PeerTubeDirectory.Sort.mostVideos)
                    Text("Most users").tag(PeerTubeDirectory.Sort.mostUsers)
                    Text("Newest").tag(PeerTubeDirectory.Sort.newest)
                } label: {
                    Label { Text("Sort") } icon: { Image(systemName: "arrow.up.arrow.down") }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityIdentifier("publicServers.sort")
            }
            ForEach(model.publicServers) { server in
                Button { Task { await model.choose(server) } } label: {
                    VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                        Text(verbatim: server.name).font(Tokens.Typography.body).foregroundStyle(Tokens.Colors.textPrimary)
                        Text(verbatim: "\(server.host) · \(server.videoCountText)")
                            .font(Tokens.Typography.caption).foregroundStyle(Tokens.Colors.textSecondary)
                        if let summary = server.summary {
                            Text(verbatim: summary).font(Tokens.Typography.caption)
                                .foregroundStyle(Tokens.Colors.textSecondary).lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(model.step == .detecting)
                .accessibilityIdentifier("instance.publicServer")
            }
            if model.loadingServers {
                ProgressView().frame(maxWidth: .infinity)
            } else if model.serversFailed {
                Button { Task { await model.loadMoreServers() } } label: { Text("Try Again") }
            } else if model.hasMoreServers {
                Button { Task { await model.loadMoreServers() } } label: { Text("Show More") }
                    .accessibilityIdentifier("publicServers.more")
            } else if model.publicServers.isEmpty, !model.serverSearch.isEmpty {
                Text("No servers match.").foregroundStyle(Tokens.Colors.textSecondary)
            }
        } header: {
            Text("Public PeerTube servers")
        } footer: {
            Text("No server? PeerTube servers host their own videos, run by communities and organisations independent of this app.")
        }
        .task { await model.loadPublicServers() }
        // Search as you type, once typing pauses.
        .task(id: model.serverSearch) {
            guard !model.publicServers.isEmpty || !model.serverSearch.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await model.reloadServers()
        }
    }
}
