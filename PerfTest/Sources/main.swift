import AppKit
import STTextView

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var scrollView: NSScrollView!
    var textView: STTextView!
    var perfTimer: Timer?
    var scrollTimer: Timer?
    var scrollSamples: [(delay: Double, work: Double)] = []
    var scrollDirection: CGFloat = 40.0 // pixels per tick — fast scroll
    var totalScrollTicks = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "STTextView Perf Test"

        let scrollable = STTextView.scrollableTextView()
        scrollView = scrollable
        textView = scrollable.documentView as! STTextView
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.showsLineNumbers = true
        textView.highlightSelectedLine = true
        textView.isHorizontallyResizable = true

        // Generate a large document (~1000 lines)
        var lines: [String] = []
        for i in 1...1000 {
            let indent = (i % 5 == 0) ? "    " : ""
            let line: String
            switch i % 7 {
            case 0: line = "\(indent)def function_\(i)(self, arg1, arg2, arg3):"
            case 1: line = "\(indent)    result = self.compute(\(i), arg1 + arg2)"
            case 2: line = "\(indent)    if result > threshold_\(i):"
            case 3: line = "\(indent)        logger.info(f\"Processing batch {batch_id} with {len(items)} items\")"
            case 4: line = "\(indent)        return {'status': 'ok', 'count': \(i), 'data': result}"
            case 5: line = "\(indent)# TODO: optimize this section for large datasets"
            default: line = "\(indent)    values = [x * \(i) for x in range(100) if x % 3 == 0]"
            }
            lines.append(line)
        }
        textView.text = lines.joined(separator: "\n")

        // Apply syntax-like coloring
        if let textStorage = (textView.textContentManager as? NSTextContentStorage)?.textStorage {
            let source = (textView.text ?? "") as NSString
            textStorage.beginEditing()
            let keywords = ["def", "if", "return", "for", "in", "self", "class", "import", "from", "True", "False", "None"]
            for keyword in keywords {
                var searchRange = NSRange(location: 0, length: source.length)
                while searchRange.location < source.length {
                    let found = source.range(of: keyword, options: NSString.CompareOptions.literal, range: searchRange)
                    if found.location == NSNotFound { break }
                    textStorage.addAttribute(.foregroundColor, value: NSColor.systemPink, range: found)
                    searchRange.location = found.location + found.length
                    searchRange.length = source.length - searchRange.location
                }
            }
            textStorage.endEditing()
        }

        // Monitor scroll performance
        scrollable.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollable.contentView
        )

        window.contentView = scrollable
        window.makeKeyAndOrderFront(nil)

        NSLog("[PerfTest] Starting automated scroll test in 1 second...")

        // Start automated scroll after 1 second
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.startScrollTest()
        }

        // Print stats every 2 seconds
        perfTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, !self.scrollSamples.isEmpty else { return }
            let avgDelay = self.scrollSamples.map(\.delay).reduce(0, +) / Double(self.scrollSamples.count)
            let maxDelay = self.scrollSamples.map(\.delay).max() ?? 0
            let count = self.scrollSamples.count
            let y = self.scrollView.contentView.bounds.origin.y
            NSLog("[PerfTest] events=%d avg_delay=%.1fms max_delay=%.1fms y=%.0f", count, avgDelay, maxDelay, y)
            self.scrollSamples.removeAll()
        }
    }

    func startScrollTest() {
        NSLog("[PerfTest] === SCROLL TEST START ===")
        // Simulate fast scrolling at ~60fps using CVDisplayLink-like timer
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.totalScrollTicks += 1

            let clipView = self.scrollView.contentView
            let maxY = (self.scrollView.documentView?.frame.height ?? 0) - clipView.bounds.height
            var newY = clipView.bounds.origin.y + self.scrollDirection

            // Bounce at top and bottom
            if newY >= maxY {
                newY = maxY
                self.scrollDirection = -abs(self.scrollDirection)
            } else if newY <= 0 {
                newY = 0
                self.scrollDirection = abs(self.scrollDirection)
            }

            clipView.scroll(to: NSPoint(x: 0, y: newY))
            self.scrollView.reflectScrolledClipView(clipView)

            // Stop after 10 seconds (~600 ticks)
            if self.totalScrollTicks >= 600 {
                self.scrollTimer?.invalidate()
                self.scrollTimer = nil
                NSLog("[PerfTest] === SCROLL TEST DONE (%d ticks) ===", self.totalScrollTicks)
                // Exit after final stats print
                Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                    NSApp.terminate(nil)
                }
            }
        }
    }

    @objc func boundsChanged() {
        let scheduleTime = CACurrentMediaTime()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let now = CACurrentMediaTime()
            let delay = (now - scheduleTime) * 1000
            self.scrollSamples.append((delay: delay, work: 0))
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
