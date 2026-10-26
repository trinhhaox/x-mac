import Cocoa

// Headless `xmac convert|formats|install-cli|--help`; returns immediately for a normal GUI launch.
ConverterCLI.runIfRequested(CommandLine.arguments)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
