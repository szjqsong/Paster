import AppKit

// Headless modes used for verification (no UI side effects on the user's session).
_ = AppLanguage.current  // pin the UI language for this launch
let arguments = CommandLine.arguments
if arguments.contains("--self-test") {
    exit(SelfTest.run())
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)

if let idx = arguments.firstIndex(of: "--snapshot"), idx + 1 < arguments.count {
    let scene = arguments.firstIndex(of: "--scene").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil } ?? "strip"
    exit(Screenshots.render(scene: scene, to: arguments[idx + 1], light: arguments.contains("--light")))
}

app.run()
