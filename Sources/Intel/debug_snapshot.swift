// Developer aid: render every screen to PNG files and quit, to check layout without screen recording.
//
//   INTEL_SNAPSHOT=/tmp/intel-shots build/Intel.app/Contents/MacOS/Intel
//
// Writes Brief.png, Proposals.png, … into that folder. The app draws its own window, so no permission
// is needed; translucent materials may render flatter than on screen.

import AppKit
import SwiftUI

enum DebugSnapshot {
    static var Directory: URL? {
        ProcessInfo.processInfo.environment["INTEL_SNAPSHOT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Show each screen in turn, save the window, then quit.
    @MainActor
    static func CaptureAllScreens(select: (Screen) -> Void, into directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? await Task.sleep(for: .seconds(3))
        var layout = ""
        for screen in Screen.allCases {
            select(screen)
            try? await Task.sleep(for: .seconds(2))
            SaveWindow(to: directory.appending(path: "\(screen.rawValue).png"))
            layout += Measure(title: screen.rawValue)
        }
        try? layout.write(to: directory.appending(path: "layout.txt"), atomically: true, encoding: .utf8)
        NSApplication.shared.terminate(nil)
    }

    /// Vertical centers (points from the window top) of the window buttons, the title and the toolbar's
    /// controls, so title-bar alignment can be checked as numbers.
    @MainActor
    private static func Measure(title: String) -> String {
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let frame = window.contentView?.superview else { return "" }
        let height = frame.bounds.height
        func Center(_ view: NSView) -> Int {
            let rect = view.convert(view.bounds, to: frame)
            return Int((height - rect.midY).rounded())
        }
        var lines = ["[\(title)] toolbar style \(window.toolbarStyle.rawValue), title bar height \(Int(height - window.contentLayoutRect.maxY))"]
        if let close = window.standardWindowButton(.closeButton) { lines.append("  window buttons y=\(Center(close))") }
        var controls: [String] = []
        func Walk(_ view: NSView) {
            if let field = view as? NSTextField, field.stringValue == title, !field.isEditable {
                lines.append("  title '\(title)' y=\(Center(field))")
            }
            if view is NSButton, Center(view) < 80 {   // buttons in the title-bar row
                controls.append("\(view.className.replacingOccurrences(of: "NS", with: ""))@y=\(Center(view))")
            }
            view.subviews.forEach(Walk)
        }
        Walk(frame)
        lines.append("  title-bar buttons: " + controls.joined(separator: " "))
        var scrollTops: [String] = []
        func Scrolls(_ view: NSView) {
            if let scroll = view as? NSScrollView, scroll.frame.width > 40 {
                let rect = scroll.convert(scroll.bounds, to: frame)
                let top = Int((height - rect.maxY).rounded())
                let contentTop = top + Int(scroll.contentInsets.top)
                scrollTops.append("x=\(Int(rect.minX)) top=\(top) content-top=\(contentTop)")
            }
            view.subviews.forEach(Scrolls)
        }
        Scrolls(frame)
        lines.append("  scroll areas: " + scrollTops.joined(separator: " | "))
        return lines.joined(separator: "\n") + "\n"
    }

    @MainActor
    private static func SaveWindow(to url: URL) {
        // The content view's superview is the window frame, so the toolbar is included.
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let frame = window.contentView?.superview,
              let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}
