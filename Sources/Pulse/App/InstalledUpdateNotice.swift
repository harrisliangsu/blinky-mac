// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import Foundation

/// What a silent install tells the reader once the new Blinky is the one running.
///
/// Install silently does not notify and does not open a window *before* the
/// install. Sparkle's automatic driver is that path, and it is the driver that
/// calls `updater:willInstallUpdateOnQuit:immediateInstallationBlock:`. The
/// windowed check does not. The process that is about to quit stores the
/// item it is installing: the display version, and that item's description.
/// The feed keeps one item, so the description is this release's notes, the
/// same ones Sparkle shows — not a stack of older releases.
///
/// The next launch reads the record. It announces only when the running
/// version is the one that was stored, then clears the record. A launch that
/// is still the previous version throws it away, so an install that did not
/// land cannot announce on some later day. A granted notification centre gets
/// a notice whose title is the version and whose body is the notes. Clicking
/// it opens those notes. Anything else — denied, not yet asked, or no centre —
/// opens the notes window on that launch, because the reader would otherwise
/// not be told. This type does not post, draw, or talk to Sparkle.
struct InstalledUpdateNotice: Equatable, Sendable {
    var version: String
    /// This release's notes as plain text. Empty when the item had none.
    var notes: String

    /// Distinct from `UpdateAnnouncement.notificationIdentifier`. That one
    /// opens the offer Sparkle is holding. This one opens the notes.
    static let notificationIdentifier = "blinky-update-installed"
    /// Not a setting. One launch consumes it. `AppSettings.Key` is the
    /// settings the persistence test spells out; this is not one of them.
    static let defaultsKey = "update.installedNotice"
    static let versionUserInfoKey = "blinkyInstalledVersion"
    static let notesUserInfoKey = "blinkyInstalledNotes"

    /// What the launch that finds a stored install should do.
    enum Launch: Equatable, Sendable {
        case absent
        /// A record for some other version. Clear it and say nothing.
        case discard
        case notify(InstalledUpdateNotice)
        case showNotes(InstalledUpdateNotice)
    }

    /// The notice to store, or nil when the version is blank.
    ///
    /// `format` is Sparkle's `itemDescriptionFormat`. Nil means HTML, which
    /// is what this feed writes. `plain-text` and `markdown` are kept as
    /// written, so a literal `<` in those notes is not eaten.
    static func make(version: String, description: String?, format: String?) -> InstalledUpdateNotice? {
        let version = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else { return nil }
        return InstalledUpdateNotice(
            version: version,
            notes: releaseNotes(description: description, format: format)
        )
    }

    static func launchAction(
        pending: InstalledUpdateNotice?,
        runningVersion: String?,
        permission: UpdateAnnouncement.Permission,
        canNotify: Bool
    ) -> Launch {
        guard let pending else { return .absent }
        let installed = pending.version.trimmingCharacters(in: .whitespacesAndNewlines)
        let running = runningVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !installed.isEmpty, running == installed else { return .discard }
        let notice = InstalledUpdateNotice(version: installed, notes: pending.notes)
        if canNotify, permission == .authorized { return .notify(notice) }
        return .showNotes(notice)
    }

    /// The notification body, and the text of the notes window.
    ///
    /// The notes when the item had any. A release whose description was
    /// empty still names the version in the title, and says here that there
    /// were no notes, rather than a blank body.
    static func announcementBody(notes: String) -> String {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return String.localized("This release did not include notes.")
        }
        return trimmed
    }

    var userInfo: [String: String] {
        [Self.versionUserInfoKey: version, Self.notesUserInfoKey: notes]
    }

    /// The notice a click carries. Nil when the version is missing, which is
    /// a notice this app did not post. Notes are already plain text.
    static func from(userInfo: [AnyHashable: Any]) -> InstalledUpdateNotice? {
        guard let version = userInfo[versionUserInfoKey] as? String else { return nil }
        let notes = userInfo[notesUserInfoKey] as? String
        return make(version: version, description: notes, format: "plain-text")
    }

    func save(to defaults: UserDefaults) {
        defaults.set(["version": version, "notes": notes], forKey: Self.defaultsKey)
    }

    static func load(from defaults: UserDefaults) -> InstalledUpdateNotice? {
        guard
            let stored = defaults.dictionary(forKey: defaultsKey),
            let version = stored["version"] as? String
        else { return nil }
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let notes = stored["notes"] as? String ?? ""
        return InstalledUpdateNotice(version: trimmed, notes: notes)
    }

    static func clear(from defaults: UserDefaults) {
        defaults.removeObject(forKey: defaultsKey)
    }

    /// Plain text of one item's description.
    ///
    /// The feed wraps the changelog in a `<style>` block, an `<h2>`, the
    /// list, and a link. The stylesheet is spacing for Sparkle's web view;
    /// leaving it in the notice would show CSS. Headings, paragraphs and
    /// list items become lines. A list item leads with a bullet. The link's
    /// label is kept and the address is not pasted after it: that is the
    /// text Sparkle shows.
    static func releaseNotes(description: String?, format: String?) -> String {
        guard let description else { return "" }
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        switch format?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "plain-text", "markdown":
            return trimmed
        default:
            return plainText(html: trimmed)
        }
    }

    private static func plainText(html: String) -> String {
        var result = ""
        var index = html.startIndex
        var skip: String?
        var pendingSpace = false

        func breakLine() {
            pendingSpace = false
            if !result.isEmpty, !result.hasSuffix("\n") {
                result.append("\n")
            }
        }

        func emit(_ text: String) {
            guard skip == nil else { return }
            for character in text {
                if character.isWhitespace {
                    pendingSpace = true
                    continue
                }
                if pendingSpace, !result.isEmpty, !result.hasSuffix("\n"), !result.hasSuffix(" ") {
                    result.append(" ")
                }
                pendingSpace = false
                result.append(character)
            }
        }

        func handle(name: String, closing: Bool) {
            if let skip {
                if closing, name == skip { selfSkipClear() }
                return
            }
            if !closing, name == "style" || name == "script" {
                skip = name
                return
            }
            switch name {
            case "br":
                breakLine()
            case "li":
                breakLine()
                if !closing { emit("• ") }
            case "p", "div", "tr", "h1", "h2", "h3", "h4", "h5", "h6":
                breakLine()
            case "ul", "ol":
                if closing { breakLine() }
            default:
                break
            }
        }

        func selfSkipClear() {
            skip = nil
        }

        while index < html.endIndex {
            if html[index] == "<", let end = html[index...].firstIndex(of: ">") {
                let inner = html[html.index(after: index)..<end]
                let tag = tagParts(inner)
                handle(name: tag.name, closing: tag.closing)
                index = html.index(after: end)
                continue
            }
            if skip == nil {
                if html[index] == "&", let decoded = entity(in: html, at: index) {
                    emit(String(decoded.character))
                    index = decoded.next
                    continue
                }
                emit(String(html[index]))
            }
            index = html.index(after: index)
        }
        return tidy(result)
    }

    private static func tagParts(_ inner: Substring) -> (name: String, closing: Bool) {
        var text = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("!--") { return ("!", false) }
        if text.hasSuffix("/") {
            text = text.dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let closing = text.hasPrefix("/")
        if closing { text = String(text.dropFirst()) }
        let name = text.prefix { character in
            character != " " && character != "\t" && character != "\n" && character != "\r" && character != "/"
        }
        return (name.lowercased(), closing)
    }

    private static func entity(in html: String, at index: String.Index) -> (character: Character, next: String.Index)? {
        guard html[index] == "&" else { return nil }
        let after = html.index(after: index)
        guard after < html.endIndex else { return nil }
        let tail = html[after...]
        guard let semi = tail.firstIndex(of: ";") else { return nil }
        guard html.distance(from: index, to: semi) <= 32 else { return nil }
        let body = html[after..<semi]
        let next = html.index(after: semi)
        if let character = namedEntity(body) {
            return (character, next)
        }
        if body.hasPrefix("#x") || body.hasPrefix("#X"), let value = UInt32(body.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(value) {
            return (Character(scalar), next)
        }
        if body.hasPrefix("#"), let value = UInt32(body.dropFirst()), let scalar = Unicode.Scalar(value) {
            return (Character(scalar), next)
        }
        return nil
    }

    private static func namedEntity(_ body: Substring) -> Character? {
        switch body {
        case "amp": "&"
        case "lt": "<"
        case "gt": ">"
        case "quot": "\""
        case "apos": "'"
        case "nbsp": " "
        default: nil
        }
    }

    private static func tidy(_ raw: String) -> String {
        var lines: [String] = []
        var blank = false
        for line in raw.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                blank = true
                continue
            }
            if blank, !lines.isEmpty { lines.append("") }
            blank = false
            lines.append(String(trimmed))
        }
        return lines.joined(separator: "\n")
    }
}
