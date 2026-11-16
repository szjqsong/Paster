import AppKit

// Headless modes used for verification (no UI side effects on the user's session).
let arguments = CommandLine.arguments
if arguments.contains("--self-test") {
    exit(SelfTest.run())
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)

if let idx = arguments.firstIndex(of: "--snapshot"), idx + 1 < arguments.count {
    exit(SelfTest.snapshot(to: arguments[idx + 1]))
}

app.run()
