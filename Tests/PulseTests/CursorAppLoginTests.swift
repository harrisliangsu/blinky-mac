// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import CommonCrypto
import Foundation
import Testing
@testable import Pulse

/// The sealed-token unwrap in `CursorAppLogin`, driven against values encrypted
/// on purpose with a known key — never against a real Cursor database or the
/// login keychain.
@Suite("Cursor app login")
struct CursorAppLoginTests {

    /// A JWT whose `exp` is far enough ahead that `session(from:)` accepts it,
    /// and whose `sub` has the `auth0|…` shape Cursor issues.
    private static let sampleToken: String = {
        let header = Data(#"{"alg":"none"}"#.utf8).base64URL
        let payload = Data(#"{"sub":"auth0|user_test","exp":4102444800}"#.utf8).base64URL
        return "\(header).\(payload).sig"
    }()

    @Test("A plaintext JWT is returned without touching the keychain")
    func plaintextPassthrough() {
        var asked = false
        let loaded = CursorAppLogin.plaintext(fromStored: sampleToken, keychainKey: {
            asked = true
            return Data()
        })
        #expect(loaded == .token(sampleToken))
        #expect(!asked)
    }

    @Test("A sealed cell decrypts with the Chromium safeStorage key")
    func sealedUnwrap() throws {
        let key = try #require(derivedKey(password: Data("pulse-test-password".utf8)))
        let sealed = try seal(sampleToken, with: key)
        let loaded = CursorAppLogin.plaintext(fromStored: sealed, keychainKey: { key })
        #expect(loaded == .token(sampleToken))
    }

    @Test("A sealed cell without a keychain key is keychainRefused, not absent")
    func sealedWithoutKey() throws {
        let key = try #require(derivedKey(password: Data("pulse-test-password".utf8)))
        let sealed = try seal(sampleToken, with: key)
        let loaded = CursorAppLogin.plaintext(fromStored: sealed, keychainKey: { nil })
        #expect(loaded == .keychainRefused)
    }

    @Test("session(from:) accepts an integer exp claim from JSONSerialization")
    func integerExpiry() {
        #expect(CursorAppLogin.session(from: sampleToken) != nil)
        let cookie = CursorAppLogin.session(from: sampleToken)?.cookie
        #expect(cookie?.hasPrefix("WorkosCursorSessionToken=user_test%3A%3A") == true)
    }

    // MARK: - Chromium seal, the inverse of BrowserCookies.decrypt

    private func derivedKey(password: Data) -> Data? {
        var key = Data(count: 16)
        let status = key.withUnsafeMutableBytes { out in
            password.withUnsafeBytes { secret in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    secret.baseAddress, secret.count,
                    "saltysalt", 9,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                    out.baseAddress, 16
                )
            }
        }
        return status == kCCSuccess ? key : nil
    }

    private func seal(_ plaintext: String, with key: Data) throws -> String {
        let body = Data(plaintext.utf8)
        var out = Data(count: body.count + kCCBlockSizeAES128)
        var moved = 0
        let status = out.withUnsafeMutableBytes { output in
            body.withUnsafeBytes { input in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyBytes.baseAddress, 16,
                        String(repeating: " ", count: 16),
                        input.baseAddress, input.count,
                        output.baseAddress, output.count,
                        &moved
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw SealError.encryptFailed(status)
        }
        var encrypted = Data("v10".utf8)
        encrypted.append(out.prefix(moved))
        return CursorAppLogin.sealedPrefix + encrypted.base64EncodedString()
    }

    private enum SealError: Error {
        case encryptFailed(CCCryptorStatus)
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
