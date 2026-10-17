import Foundation
import Testing
@testable import Core

/// Live: signing in to each kind of account with the test account, then reading its
/// subscriptions. Skipped without the instance URLs and `INSTANCE_USERNAME`/`INSTANCE_PASSWORD`.
struct AccountContractTests {
    private let environment = ProcessInfo.processInfo.environment

    private func credentials() -> (String, String)? {
        guard let user = environment["INSTANCE_USERNAME"], let password = environment["INSTANCE_PASSWORD"] else { return nil }
        return (user, password)
    }

    @Test func pipedSignInReadsSubscriptions() async throws {
        guard let url = environment["PIPED_URL"].flatMap(URL.init(string:)), let (user, password) = credentials() else { return }
        let instance = InstanceConfig(kind: .piped, displayName: "piped", apiURL: url)
        let token = try await AccountSignIn.signIn(instance, username: user, password: password, deviceName: "Tests")
        #expect(!(try await PipedAccount(instance: instance, token: token).subscriptions()).isEmpty)
        await #expect(throws: AccountSignIn.Failure.self) {
            try await AccountSignIn.signIn(instance, username: user, password: password + "x", deviceName: "Tests")
        }
    }

    @Test func invidiousSignInReadsSubscriptionsAndFeed() async throws {
        guard let url = environment["INVIDIOUS_URL"].flatMap(URL.init(string:)), let (user, password) = credentials() else { return }
        let instance = InstanceConfig(kind: .invidious, displayName: "invidious", apiURL: url)
        let session = try await AccountSignIn.signIn(instance, username: user, password: password, deviceName: "Tests")
        let account = InvidiousAccount(instance: instance, session: session)
        #expect(!(try await account.subscriptions()).isEmpty)
        #expect(!(try await account.accountFeed(page: 0)).items.isEmpty)
    }

    @Test func ytZeroSignInWithPassword() async throws {
        guard environment["ACCOUNT_YTZERO"] == "1", let url = environment["YTZERO_URL"].flatMap(URL.init(string:)),
              let (user, password) = credentials() else { return }
        let instance = InstanceConfig(kind: .ytZero, displayName: "ytzero", apiURL: url)
        let token = try await AccountSignIn.signIn(instance, username: user, password: password, deviceName: "Specto tests")
        #expect(!token.isEmpty)
    }
}
