import SwiftUI
import UniformTypeIdentifiers
import Core
import Library
import DesignSystem

/// Instances and subscription import: the onboarding flow and the matching Settings section.
public struct InstancesScreen: View {
    private let instances: InstanceStore
    private let subscriptions: SubscriptionStore
    private let secrets: any SecretStore
    private let deviceName: String
    private let onChange: () -> Void
    private let onImported: ([ChannelSummary]) -> Void
    private let checkHealth: (() async -> [HealthSample])?
    private let startsAdding: Bool
    private let signIn: ((InstanceConfig, String, String) async throws -> Void)?
    private let signOut: ((InstanceConfig) -> Void)?
    /// Instances with a stored sign-in, and the one that owns subscriptions (the first).
    @State private var signedIn: Set<UUID> = []
    @State private var signingIn: InstanceConfig?

    @State private var list: [InstanceConfig] = []
    @State private var subscriptionCount = 0
    @State private var addModel: AddInstanceModel?
    @State private var importing = false
    @State private var importMessage: String?
    @State private var status: [UUID: InstanceStatus] = [:]

    /// - Parameters:
    ///   - onChange: instances were added or removed (the app rebuilds its sources).
    ///   - onImported: channels were imported (the app backfills their videos).
    ///   - checkHealth: probes every instance, for each row's status and latency.
    ///   - startsAdding: open Add Instance straight away when there are none yet (first launch).
    public init(instances: InstanceStore, subscriptions: SubscriptionStore, secrets: any SecretStore,
                deviceName: String, onChange: @escaping () -> Void,
                onImported: @escaping ([ChannelSummary]) -> Void,
                checkHealth: (() async -> [HealthSample])? = nil, startsAdding: Bool = false,
                signIn: ((InstanceConfig, String, String) async throws -> Void)? = nil,
                signOut: ((InstanceConfig) -> Void)? = nil) {
        self.startsAdding = startsAdding
        self.signIn = signIn
        self.signOut = signOut
        self.instances = instances
        self.subscriptions = subscriptions
        self.secrets = secrets
        self.deviceName = deviceName
        self.onChange = onChange
        self.onImported = onImported
        self.checkHealth = checkHealth
    }

    public var body: some View {
        List {
            Section {
                ForEach(list) { instance in
                    InstanceRow(instance: instance, status: status[instance.id] ?? (checkHealth == nil ? nil : .checking),
                                account: accountState(instance))
                        .contextMenu { accountActions(instance) }
                        #if os(iOS)
                        .swipeActions(edge: .leading) { accountActions(instance) }
                        #endif
                }
                .onDelete(perform: delete)
                Button { startAdding() } label: {
                    Label { Text("Add Instance") } icon: { Image(systemName: "plus") }
                }
                .accessibilityIdentifier("instances.add")
            } header: {
                Text("Instances")
            } footer: {
                Text("Your own Piped, Invidious or YT Zero server. Nothing is sent anywhere else.")
            }

            Section {
                #if os(tvOS)
                // No files on Apple TV: import on iPhone or iPad, and sync brings the list here.
                Text("^[\(subscriptionCount) channel](inflect: true)")
                #else
                Button { importing = true } label: {
                    Label { Text("Import Subscriptions…") } icon: { Image(systemName: "square.and.arrow.down") }
                }
                if let importMessage {
                    Text(importMessage).foregroundStyle(Tokens.Colors.textSecondary)
                }
                #endif
            } header: {
                Text("Subscriptions")
            } footer: {
                #if os(tvOS)
                Text("Import subscriptions on your iPhone or iPad. They sync to Apple TV through iCloud or YT Zero.")
                #else
                Text("^[\(subscriptionCount) channel](inflect: true). Import a Google Takeout subscriptions.csv, or an export from NewPipe, FreeTube or Piped.")
                #endif
            }
        }
        .navigationTitle(Text("Instances"))
        .sheet(item: $signingIn) { instance in
            NavigationStack {
                SignInView(instance: instance) { username, password in
                    try await signIn?(instance, username, password)
                    reload()
                }
            }
        }
        .task {
            reload()
            if startsAdding, list.isEmpty, addModel == nil { startAdding() }
        }
        // Again whenever the list changes: a new instance joins the app's sources first.
        .task(id: list.map(\.id)) { await probe() }
        .refreshable { await probe() }
        .sheet(item: $addModel) { model in
            NavigationStack { AddInstanceView(model: model) }
        }
        #if !os(tvOS)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.commaSeparatedText, .json, .xml, .plainText, .data]) { result in
            importSubscriptions(result)
        }
        #endif
    }

    private func reload() {
        list = (try? instances.all()) ?? []
        signedIn = Set(list.filter { secrets.secret(for: InstanceConfig.tokenKey(for: $0.id)) != nil }.map(\.id))
        subscriptionCount = (try? subscriptions.channels().count) ?? 0
    }

    private func probe() async {
        guard let checkHealth else { return }
        let samples = await checkHealth()
        status = Dictionary(samples.map { ($0.instanceID, InstanceStatus($0)) }, uniquingKeysWith: { first, _ in first })
    }

    /// The first signed-in instance in this order owns YouTube subscriptions (ADR 0017).
    private func accountState(_ instance: InstanceConfig) -> InstanceRow.Account {
        guard instance.kind != .peerTube, signedIn.contains(instance.id) else { return .none }
        let owner = list.first { $0.kind != .peerTube && signedIn.contains($0.id) }
        return owner?.id == instance.id ? .subscriptions : .signedIn
    }

    @ViewBuilder
    private func accountActions(_ instance: InstanceConfig) -> some View {
        if signIn != nil, instance.kind == .piped || instance.kind == .invidious {
            if signedIn.contains(instance.id) {
                Button(role: .destructive) { signOut?(instance); reload() } label: {
                    Label { Text("Sign Out") } icon: { Image(systemName: "person.crop.circle.badge.minus") }
                }
            } else {
                Button { signingIn = instance } label: {
                    Label { Text("Sign In…") } icon: { Image(systemName: "person.crop.circle") }
                }
                .tint(.accentColor)
            }
        }
    }

    private func startAdding() {
        addModel = AddInstanceModel(instances: instances, secrets: secrets, deviceName: deviceName) { _ in
            reload()
            onChange()
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            let instance = list[index]
            try? instances.remove(instance.id)
            secrets.setSecret(nil, for: AddInstanceModel.tokenKey(for: instance.id))
        }
        reload()
        onChange()
    }

    private func importSubscriptions(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let channels = try SubscriptionImport.parse(try Data(contentsOf: url))
            try subscriptions.subscribe(channels)
            importMessage = String(localized: "Imported \(channels.count) channels.")
            reload()
            onImported(channels)
        } catch SubscriptionImport.Failure.unrecognisedFormat {
            importMessage = String(localized: "That file isn't a subscriptions export this app understands.")
        } catch SubscriptionImport.Failure.empty {
            importMessage = String(localized: "No channels found in that file.")
        } catch {
            importMessage = String(localized: "Couldn't import: \(error.localizedDescription)")
        }
    }
}

extension AddInstanceModel: Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

/// A row's reachability, formatted once when the probe returns.
struct InstanceStatus: Equatable {
    enum Health { case checking, online, unreachable }
    let health: Health
    let text: String

    static let checking = InstanceStatus(health: .checking, text: String(localized: "Checking…"))

    init(health: Health, text: String) {
        self.health = health
        self.text = text
    }

    init(_ sample: HealthSample) {
        if sample.isHealthy {
            health = .online
            if let latency = sample.latency {
                let ms = Double(latency.components.seconds) * 1000 + Double(latency.components.attoseconds) / 1e15
                let formatted = Measurement(value: ms.rounded(), unit: UnitDuration.milliseconds)
                    .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
                text = String(localized: "Online · \(formatted)")
            } else {
                text = String(localized: "Online")
            }
        } else {
            health = .unreachable
            text = String(localized: "Unreachable")
        }
    }
}

private struct InstanceRow: View {
    enum Account { case none, signedIn, subscriptions }

    let instance: InstanceConfig
    let status: InstanceStatus?
    let account: Account

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            Text(instance.displayName).font(Tokens.Typography.body)
            HStack(spacing: Tokens.Spacing.xs) {
                Text(instance.kind.displayName)
                if let status {
                    Text(verbatim: "·").accessibilityHidden(true)
                    Image(systemName: status.health == .unreachable ? "exclamationmark.circle.fill" : "circle.fill")
                        .imageScale(.small)
                        .foregroundStyle(color(status.health))
                        .accessibilityHidden(true)
                    Text(status.text)
                }
            }
            .font(Tokens.Typography.caption)
            .foregroundStyle(Tokens.Colors.textSecondary)
            switch account {
            case .none: EmptyView()
            case .signedIn:
                Label { Text("Signed in") } icon: { Image(systemName: "person.crop.circle.fill") }
                    .font(Tokens.Typography.caption).foregroundStyle(Tokens.Colors.textSecondary)
            case .subscriptions:
                Label { Text("Signed in · Your subscriptions") } icon: { Image(systemName: "person.crop.circle.fill") }
                    .font(Tokens.Typography.caption).foregroundStyle(Tokens.Colors.accent)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("instance.row")
    }

    private func color(_ health: InstanceStatus.Health) -> Color {
        switch health {
        case .checking: .secondary
        case .online: .green
        case .unreachable: .orange
        }
    }
}

extension SourceKind {
    var displayName: String {
        switch self {
        case .piped: "Piped"
        case .invidious: "Invidious"
        case .ytZero: "YT Zero"
        case .peerTube: "PeerTube"
        }
    }
}

/// Username and password for a Piped or Invidious account. The password goes only to that
/// instance; the app keeps what it answers (a token or a session) in the Keychain.
private struct SignInView: View {
    let instance: InstanceConfig
    let submit: (String, String) async throws -> Void
    @State private var username = ""
    @State private var password = ""
    @State private var working = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextField(text: $username) { Text("Username") }
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("signIn.username")
                SecureField(text: $password) { Text("Password") }
                    .textContentType(.password)
                    .accessibilityIdentifier("signIn.password")
                    .onSubmit { Task { await go() } }
            } footer: {
                if let error {
                    Text(error).foregroundStyle(.red)
                } else {
                    Text("Your subscriptions on \(instance.displayName) become the app's. Any you follow here that the account lacks are added to it.")
                }
            }
        }
        .navigationTitle(Text("Sign In"))
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Text("Cancel") }
            }
            ToolbarItem(placement: .confirmationAction) {
                if working {
                    ProgressView()
                } else {
                    Button { Task { await go() } } label: { Text("Sign In") }
                        .disabled(username.isEmpty || password.isEmpty)
                        .accessibilityIdentifier("signIn.submit")
                }
            }
        }
    }

    private func go() async {
        working = true
        error = nil
        defer { working = false }
        do {
            try await submit(username, password)
            dismiss()
        } catch AccountSignIn.Failure.rejected {
            error = String(localized: "That username and password didn't work.")
        } catch {
            self.error = String(localized: "Couldn't sign in: \(error.localizedDescription)")
        }
    }
}
