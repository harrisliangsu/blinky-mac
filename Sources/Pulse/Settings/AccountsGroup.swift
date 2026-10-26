// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit
import SwiftUI

/// Signing in to another subscription of the same provider, and getting
/// rid of one.
///
/// Only shown where it can work. The other providers are read from a login
/// their own tool stored, and that store holds exactly one — a second
/// account of theirs is not something Pulse can be shown, so offering it
/// would be a control that cannot do anything.
struct AccountsGroup: View {
    let account: AccountKey
    let settings: AppSettings
    let signIn: ProviderSignInModel
    let navigation: SettingsNavigation

    @ViewBuilder
    var body: some View {
        if account.provider.supportsMultipleAccounts {
            SettingsGroup(String.localized("Accounts")) {
                if account.isPrimary, account.provider == .kimiCode {
                    kimiPrimaryAccountRow(account)
                }
                if account.isPrimary, account.provider == .grok {
                    grokPrimaryAccountRow(account)
                }

                // Codex-shaped extras. Kimi hides "Add another" until the primary
                // subscription is signed in, so the first Sign in… cannot be
                // mistaken for adding a second ring. Grok does not: the CLI
                // login already serves the primary ring, and another account
                // is a separate sign-in. Extra accounts always get
                // "Sign in again…".
                if !account.isPrimary || account.provider != .kimiCode || kimiSignedIn {
                    if account.isPrimary, account.provider == .kimiCode || account.provider == .grok {
                        SettingsRowDivider()
                    }
                    SettingsRow(
                        account.isPrimary ? String.localized("Add another account") : String.localized("Sign in again…"),
                        // The one thing someone should know before they start:
                        // whose name is on the page that opens.
                        subtitle: String.localized("Opens the provider's own sign-in page.")
                    ) {
                        // One sign-in at a time, and its Cancel, code and
                        // error belong to the provider it was started for:
                        // a Codex device code shown on the Claude Code pane
                        // reads as Claude Code asking for it.
                        // Grok's primary login has its own row, so this button
                        // does not cancel that attempt.
                        if showsCancelForThisRow {
                            Button(String.localized("Cancel")) { signIn.cancelSignIn() }
                        } else {
                            Button(String.localized("Sign in…")) {
                                signIn.signIn(to: account.provider, replacing: account.isPrimary ? nil : account)
                            }
                            .disabled(signIn.signingIn != nil)
                        }
                    }
                }

                // While a device-code sign-in is waiting, the code is the
                // whole interaction: it is typed on the provider's page,
                // not here, and nothing comes back to this Mac. Kept outside
                // the "Add another" gate so a primary Kimi sign-in still
                // shows its code on this pane.
                if let devicePrompt = signIn.devicePrompt, signIn.signingIn == account.provider {
                        SettingsRowDivider()
                        SettingsRow(
                            String.localized("Code"),
                            // The sign-in half is not decoration: OpenAI's own
                            // hand-off to a Google account fails with
                            // `token_exchange_failed` when the browser has no
                            // session, and this row is the only place that
                            // says so. Which half is said depends on whether
                            // the provider's own link already carries the
                            // code — telling someone to paste on a page that
                            // filled itself in is an instruction to undo.
                            subtitle: devicePrompt.prefilled
                                ? String.localized("Already on the page. Sign in there first if asked, then approve it.")
                                : String.localized("Copied. Sign in there first if asked, then paste it.")
                        ) {
                            HStack(spacing: 10) {
                                Text(devicePrompt.userCode)
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .textSelection(.enabled)

                                Button(String.localized("Copy")) { SettingsClipboard.copy(devicePrompt.userCode) }

                                Button(String.localized("Open page")) {
                                    NSWorkspace.shared.open(devicePrompt.verificationURL)
                                }
                            }
                        }
                    }

                    if let signInError = signIn.signInError, signInError.provider == account.provider {
                        // Primary Kimi already surfaces the message in its row
                        // subtitle; skip the duplicate Sign-in row there.
                        if !(account.isPrimary && (account.provider == .kimiCode || account.provider == .grok)) {
                            SettingsRowDivider()
                            SettingsRow(String.localized("Sign-in"), subtitle: signInError.message) { EmptyView() }
                        }
                    }
                if !account.isPrimary {
                    SettingsRowDivider()
                    SettingsRow(String.localized("Name")) {
                        TextField("", text: Binding(
                            get: { settings.label(for: account) },
                            set: { settings.rename(account, to: $0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: SettingsLayout.controlWidth)
                    }

                    SettingsRowDivider()

                    SettingsRow(
                        String.localized("Remove account"),
                        subtitle: String.localized("Forgets its login and takes it off the rail.")
                    ) {
                        Button(String.localized("Remove"), role: .destructive) {
                            AccountCredentialStore.set(nil, for: account)
                            settings.removeAccount(account)
                            navigation.pane = .appearance
                        }
                    }
                }
            }
        }
    }

    /// The primary Kimi login is a file, so this reads a counter the sign-in
    /// model bumps when that file changes.
    private var kimiSignedIn: Bool {
        _ = signIn.loginRevision
        return AccountCredentialStore.credentials(for: AccountKey(.kimiCode)) != nil
    }

    /// Blinky's primary Grok login, same file, same counter.
    private var grokSignedIn: Bool {
        _ = signIn.loginRevision
        return AccountCredentialStore.credentials(for: AccountKey(.grok)) != nil
    }

    /// Cancel on the add / sign-in-again row. Grok's primary sign-in cancels
    /// from its own row, so this one stays a way to add an account.
    private var showsCancelForThisRow: Bool {
        guard signIn.signingIn == account.provider else { return false }
        if account.isPrimary, account.provider == .grok, signIn.signingInTarget == AccountKey(.grok) {
            return false
        }
        return true
    }

    /// What the signed-in row says. Built here so `localized:` stays a literal.
    private func grokSignedInSubtitle(_ source: UsageSource) -> String {
        switch source {
        case .endpoint:
            String.localized("Signed in. The CLI login is used instead.")
        case .tooling, .desktopApp:
            String.localized("Signed in. Blinky holds a login for this Mac.")
        case .automatic:
            String.localized("Signed in. Blinky uses this when the CLI login is missing or refused.")
        }
    }

    /// The login Blinky keeps for the primary Grok account when the CLI's
    /// token is missing or refused. Separate from "Add another account".
    private func grokPrimaryAccountRow(_ account: AccountKey) -> some View {
        SettingsRow(
            String.localized("Grok account"),
            subtitle: (signIn.signInError?.provider == .grok ? signIn.signInError?.message : nil)
                ?? (grokSignedIn
                    ? grokSignedInSubtitle(settings.source(for: account))
                    : String.localized("Opens xAI's sign-in page. Blinky keeps this login and renews it, and does not change the CLI's."))
        ) {
            if signIn.signingInTarget == AccountKey(.grok) {
                Button(String.localized("Cancel")) { signIn.cancelSignIn() }
            } else if grokSignedIn {
                Button(String.localized("Sign out")) {
                    signIn.forgetPrimaryLogin(account)
                }
            } else {
                Button(String.localized("Sign in…")) {
                    signIn.signIn(to: .grok, replacing: AccountKey(.grok))
                }
                .disabled(signIn.signingIn != nil)
            }
        }
    }

    /// The primary Kimi Code subscription, signed in the same way Codex extras
    /// are: a device-code button in Accounts, not a key in Connection.
    private func kimiPrimaryAccountRow(_ account: AccountKey) -> some View {
        SettingsRow(
            String.localized("Kimi Code account"),
            subtitle: (signIn.signInError?.provider == .kimiCode ? signIn.signInError?.message : nil)
                ?? (kimiSignedIn
                    ? (settings.source(for: account) == .endpoint
                        ? String.localized("Signed in. The API key in Connection is used instead.")
                        : String.localized("Signed in. Blinky holds a login for this Mac."))
                    : String.localized("Opens Kimi Code's own page. Blinky only reads usage."))
        ) {
            if signIn.signingIn == .kimiCode, !kimiSignedIn {
                Button(String.localized("Cancel")) { signIn.cancelSignIn() }
            } else if kimiSignedIn {
                Button(String.localized("Sign out")) {
                    signIn.forgetPrimaryLogin(account)
                }
            } else {
                Button(String.localized("Sign in…")) {
                    signIn.signIn(to: .kimiCode, replacing: AccountKey(.kimiCode))
                }
                .disabled(signIn.signingIn != nil)
            }
        }
    }
}
