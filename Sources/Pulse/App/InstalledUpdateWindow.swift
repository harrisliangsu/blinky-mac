// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
import AppKit

/// The notes for a silent install, when a notification cannot carry them or
/// the reader opens the notification.
///
/// An accessory app's window opens behind everything else unless something
/// makes the process activable first. This uses the same Dock path as
/// Sparkle's offer (`DockPresence.setInstalledNotesVisible`), including while
/// the while-open Dock switch is off, and then orders the window front.
@MainActor
final class InstalledUpdateWindowController {
    private let dock: DockPresence
    private var window: InstalledUpdateWindow?
    private var textView: NSTextView?
    private var doneButton: NSButton?
    private let buttonTarget = ButtonTarget()

    init(dock: DockPresence) {
        self.dock = dock
    }

    func show(_ notice: InstalledUpdateNotice) {
        let window = window ?? makeWindow()
        self.window = window
        window.title = String.localized("Blinky \(notice.version) is installed")
        doneButton?.title = String.localized("Done")
        textView?.string = InstalledUpdateNotice.announcementBody(notes: notice.notes)
        window.onClose = { [weak self, weak window] in
            self?.dock.setInstalledNotesVisible(false)
            self?.dock.apply(closing: window)
        }
        dock.setInstalledNotesVisible(true)
        dock.apply(showingWindow: window)
        if let textView {
            let visible = textView.enclosingScrollView?.contentSize.width ?? 0
            let fallback = window.contentLayoutRect.width - 36
            let width = max(visible, fallback, 200)
            textView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        }
    }

    private func makeWindow() -> InstalledUpdateWindow {
        let window = InstalledUpdateWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 360, height: 220)

        let content = NSView()
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.borderType = .noBorder

        let text = NSTextView()
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.drawsBackground = false
        text.font = .systemFont(ofSize: 13)
        text.textColor = .labelColor
        text.textContainerInset = NSSize(width: 2, height: 4)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.minSize = NSSize(width: 0, height: 0)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 440, height: CGFloat.greatestFiniteMagnitude)
        text.frame = NSRect(x: 0, y: 0, width: 440, height: 240)
        scroll.documentView = text

        buttonTarget.window = window
        let button = NSButton(title: String.localized("Done"), target: buttonTarget, action: #selector(ButtonTarget.click(_:)))
        button.keyEquivalent = "\r"
        button.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(scroll)
        content.addSubview(button)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            button.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 12),
            button.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            button.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
        window.contentView = content
        window.center()
        dock.track(window)
        textView = text
        doneButton = button
        return window
    }
}

/// Escape closes it. The text view is not editable, and a key that reaches
/// the window still has to dismiss the notes: the reader opened them to read,
/// and Return is already the Done button.
private final class InstalledUpdateWindow: NSWindow {
    var onClose: (() -> Void)?

    override func close() {
        let notify = onClose
        onClose = nil
        notify?()
        super.close()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            close()
            return
        }
        super.sendEvent(event)
    }
}

/// `NSButton` retains its target. A separate object, rather than the window,
/// so the button does not keep the window alive on its own. The click arrives
/// on the main thread; `close()` is main-actor work.
private final class ButtonTarget: NSObject {
    /// The window is main-actor isolated. The button calls this from AppKit,
    /// on the main thread, and the reference is only used to close it there.
    nonisolated(unsafe) weak var window: InstalledUpdateWindow?

    @objc func click(_ sender: Any?) {
        let window = window
        MainActor.assumeIsolated {
            window?.close()
        }
    }
}
