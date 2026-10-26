// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import Foundation
import Observation

/// Signing in from Settings: another subscription of a provider that can have
/// more than one (the browser flow, or a device code), and Copilot's own
/// GitHub sign-in.
///
/// The shell holds it, not a pane. A device-code sign-in polls for fifteen
/// minutes, and the Cancel button, the code and the error have to be where
/// the reader left them when they come back to the provider's pane.
@MainActor
@Observable
final class ProviderSignInModel {
    private let store: UsageStore
    private let settings: AppSettings
    private let navigation: SettingsNavigation
    private let credentialModel: ProviderCredentialModel

    init(store: UsageStore, settings: AppSettings, navigation: SettingsNavigation, credentials: ProviderCredentialModel) {
        self.store = store
        self.settings = settings
        self.navigation = navigation
        self.credentialModel = credentials
    }

    /// The provider a browser sign-in is currently open for, and what went
    /// wrong with the last one.
    var signingIn: Provider?
    /// The account this sign-in writes to. Nil means a new account. The
    /// primary Grok row and "Add another account" each cancel only their own
    /// attempt, so one button does not take the other's code off the pane.
    var signingInTarget: AccountKey?
    var signInError: (provider: Provider, message: String)?
    /// Shown while a device-code sign-in is waiting: the code the provider
    /// gave, and where to type it.
    var devicePrompt: OAuthLogin.DevicePrompt?
    /// Copilot's own sign-in, which is GitHub's device flow rather than the
    /// one the added-account button drives.
    var githubPrompt: GitHubDeviceLogin.Prompt?
    var githubTask: Task<Void, Never>?
    var githubError: String?
    /// Held so it can be called off. A device-code sign-in polls for fifteen
    /// minutes, and a sign-in that failed in the browser gives this side no
    /// sign at all — without a way out the button stays disabled for the whole
    /// quarter of an hour.
    var signInTask: Task<Void, Never>?
    /// Bumped when a primary login Blinky holds (Kimi Code, Grok) is written
    /// or forgotten. `AccountCredentialStore` is a file, not something
    /// SwiftUI can observe.
    var loginRevision = 0

    /// Whether a sign-in of either kind is running, which holds the
    /// diagnostics' own sign-in remedy back.
    var isBusy: Bool { signingIn != nil || githubTask != nil }

    /// The Cancel on an added account's sign-in.
    /// Drops Kimi Code's primary subscription login and asks for a fresh reading.
    func forgetPrimaryLogin(_ account: AccountKey) {
        _ = AccountCredentialStore.set(nil, for: account)
        loginRevision += 1
        signInError = nil
        store.refresh(account)
    }

    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        signingIn = nil
        signingInTarget = nil
        devicePrompt = nil
    }

    /// Copilot's Sign out: forgets the token and asks for a fresh reading.
    func signOutOfGitHub(account: AccountKey) {
        _ = APIKeyStore.setKey(nil, for: .copilot)
        credentialModel.apiKey = ""
        credentialModel.savedKey = ""
        githubError = nil
        store.loadAPIKeys()
        store.refresh(account)
    }

    /// GitHub's device flow, for Copilot's quota.
    func startGitHubSignIn() {
        githubError = nil
        githubTask = Task { [self] in
            defer {
                // Only the attempt still on screen clears the pane; a cancelled
                // one has already had its state cleared by the button.
                if !Task.isCancelled {
                    githubTask = nil
                    githubPrompt = nil
                }
            }
            do {
                let prompt = try await GitHubDeviceLogin.start()
                githubPrompt = prompt
                // The clipboard is the whole convenience here: GitHub will not
                // pre-fill its field from a link, deliberately, because that is
                // the device-code phishing attack. A paste still leaves the
                // consent where it belongs.
                SettingsClipboard.copy(prompt.userCode)
                NSWorkspace.shared.open(prompt.verificationURL)

                let token = try await GitHubDeviceLogin.awaitToken(prompt)
                try Task.checkCancellation()
                guard APIKeyStore.setKey(token, for: .copilot) else {
                    githubError = String.localized("Couldn't save the login on this Mac.")
                    return
                }
                if navigation.pane == .account(AccountKey(.copilot)) {
                    credentialModel.apiKey = token
                    credentialModel.savedKey = token
                }
                store.loadAPIKeys()
                store.refresh(AccountKey(.copilot))
            } catch let failure as GitHubDeviceLogin.Failure {
                if !Task.isCancelled { githubError = failure.message }
            } catch is CancellationError {
                // Cancelling is not a failure, and nothing about it belongs in
                // a pane that may already be showing the next attempt.
            } catch {
                if !Task.isCancelled { githubError = String.localized("Sign-in was cancelled.") }
            }
        }
    }

    func endGitHubSignIn() {
        githubTask?.cancel()
        githubTask = nil
        githubPrompt = nil
        githubError = nil
    }

    /// Runs the browser sign-in, then keeps whatever came back.
    func signIn(to provider: Provider, replacing existing: AccountKey? = nil) {
        signingIn = provider
        signingInTarget = existing
        signInError = nil

        signInTask = Task { [self] in
            defer {
                // Only an attempt that is still the one on screen clears the
                // pane. A cancelled one has already had its state cleared by
                // the button that cancelled it, and by the time it unwinds the
                // user may well have started another — which would otherwise
                // lose its Cancel button and its code to a sign-in nobody is
                // waiting for any more.
                if !Task.isCancelled {
                    signingIn = nil
                    signingInTarget = nil
                    devicePrompt = nil
                    signInTask = nil
                }
            }
            do {
                let credentials: AccountCredentials
                if provider == .grokBot {
                    // Cursor has no OAuth for a third party to drive: its page
                    // takes a challenge and a nonce and the tokens are polled
                    // for afterwards. Nothing comes back to this Mac and there
                    // is no code to type, so this branch shows neither.
                    credentials = try await CursorWebLogin.signIn()
                } else if OAuthLogin.usesDeviceCode(provider) {
                    // A code shown on the provider's own page. No local
                    // port to collide with the CLI's sign-in, and nothing
                    // redirected back to this Mac. Whether the page fills the
                    // code in itself is the provider's decision — GitHub and
                    // OpenAI send no pre-filled link, xAI does — so the code
                    // goes on the clipboard either way and the row's subtitle
                    // follows `DevicePrompt.prefilled`.
                    let prompt = try await OAuthLogin.startDevice(provider)
                    devicePrompt = prompt
                    // On the clipboard the moment it exists, like GitHub's. The
                    // same reason applies here: neither page will pre-fill from
                    // a link, so a paste is the shortest honest route.
                    SettingsClipboard.copy(prompt.userCode)
                    NSWorkspace.shared.open(prompt.verificationURL)
                    credentials = try await OAuthLogin.awaitDevice(prompt, for: provider)
                } else {
                    credentials = try await OAuthLogin.signIn(to: provider)
                }
                // Seeded from whatever the provider said about the account, so
                // two subscriptions are not both offered as "Codex".
                try Task.checkCancellation()
                // Primary Kimi subscription, and Grok's own fallback login:
                // write onto the primary key, no extra ring. An added account
                // still goes through the branch below.
                if let existing, existing == AccountKey(provider), provider == .kimiCode || provider == .grok {
                    guard AccountCredentialStore.set(credentials, for: existing) else {
                        signInError = (provider, String.localized("Couldn't save the login on this Mac."))
                        return
                    }
                    loginRevision += 1
                    store.refresh(existing)
                    return
                }
                if let existing, !settings.allAccounts.contains(existing) { return }
                let added = existing ?? settings.addAccount(provider, label: Self.label(for: credentials, provider: provider, in: settings))
                guard AccountCredentialStore.set(credentials, for: added) else {
                    if existing == nil { settings.removeAccount(added) }
                    signInError = (provider, String.localized("Couldn't save the login on this Mac."))
                    return
                }
                store.refresh(added)
                navigation.pane = .account(added)
            } catch let failure as OAuthLogin.Failure {
                if !Task.isCancelled { signInError = (provider, failure.message) }
            } catch is CancellationError {
                // Cancelling is not a failure, and nothing about it belongs in
                // a pane that may already be showing the next attempt.
            } catch {
                if !Task.isCancelled { signInError = (provider, String.localized("Sign-in was cancelled.")) }
            }
        }
    }

    /// What to call a newly added account.
    ///
    /// The part of the address before the "@", because the card's header is
    /// one line at a fixed width and a whole email address spends all of it.
    /// A provider that names nothing gets a number, which at least counts.
    /// Either way it is the user's to change.
    private static func label(for credentials: AccountCredentials, provider: Provider, in settings: AppSettings) -> String {
        if let name = credentials.accountName?.split(separator: "@").first, !name.isEmpty {
            return String(name)
        }

        let existing = settings.extraAccounts.filter { $0.provider == provider }.count
        return "\(provider.displayName) \(existing + 2)"
    }
}

/// The system clipboard, for the codes a sign-in puts there and the commands a
/// remedy offers.
enum SettingsClipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
