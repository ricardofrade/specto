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
    public init(instances: InstanceStore, subscriptions: SubscriptionStore, secrets: any SecretStore,
                deviceName: String, onChange: @escaping () -> Void,
                onImported: @escaping ([ChannelSummary]) -> Void,
                checkHealth: (() async -> [HealthSample])? = nil) {
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
                    InstanceRow(instance: instance, status: status[instance.id] ?? (checkHealth == nil ? nil : .checking))
                }
                .onDelete(perform: delete)
                Button { startAdding() } label: {
                    Label { Text("Add Instance") } icon: { Image(systemName: "plus") }
                }
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
        .task { reload() }
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
        subscriptionCount = (try? subscriptions.channels().count) ?? 0
    }

    private func probe() async {
        guard let checkHealth else { return }
        let samples = await checkHealth()
        status = Dictionary(samples.map { ($0.instanceID, InstanceStatus($0)) }, uniquingKeysWith: { first, _ in first })
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
    let instance: InstanceConfig
    let status: InstanceStatus?

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
        }
    }
}
