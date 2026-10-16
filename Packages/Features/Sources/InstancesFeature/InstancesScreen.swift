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

    @State private var list: [InstanceConfig] = []
    @State private var subscriptionCount = 0
    @State private var addModel: AddInstanceModel?
    @State private var importing = false
    @State private var importMessage: String?

    /// - Parameters:
    ///   - onChange: instances were added or removed (the app rebuilds its sources).
    ///   - onImported: channels were imported (the app backfills their videos).
    public init(instances: InstanceStore, subscriptions: SubscriptionStore, secrets: any SecretStore,
                deviceName: String, onChange: @escaping () -> Void,
                onImported: @escaping ([ChannelSummary]) -> Void) {
        self.instances = instances
        self.subscriptions = subscriptions
        self.secrets = secrets
        self.deviceName = deviceName
        self.onChange = onChange
        self.onImported = onImported
    }

    public var body: some View {
        List {
            Section {
                ForEach(list) { instance in
                    InstanceRow(instance: instance)
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
                Button { importing = true } label: {
                    Label { Text("Import Subscriptions…") } icon: { Image(systemName: "square.and.arrow.down") }
                }
                if let importMessage {
                    Text(importMessage).foregroundStyle(Tokens.Colors.textSecondary)
                }
            } header: {
                Text("Subscriptions")
            } footer: {
                Text("^[\(subscriptionCount) channel](inflect: true). Import a Google Takeout subscriptions.csv, or an export from NewPipe, FreeTube or Piped.")
            }
        }
        .navigationTitle(Text("Instances"))
        .task { reload() }
        .sheet(item: $addModel) { model in
            NavigationStack { AddInstanceView(model: model) }
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.commaSeparatedText, .json, .xml, .plainText, .data]) { result in
            importSubscriptions(result)
        }
    }

    private func reload() {
        list = (try? instances.all()) ?? []
        subscriptionCount = (try? subscriptions.channels().count) ?? 0
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

private struct InstanceRow: View {
    let instance: InstanceConfig

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            Text(instance.displayName).font(Tokens.Typography.body)
            Text(instance.kind.displayName).font(Tokens.Typography.caption).foregroundStyle(Tokens.Colors.textSecondary)
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
