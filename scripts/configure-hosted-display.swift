import CoreGraphics
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

// This diagnostic is limited to disposable GitHub-hosted runners.
let environment = ProcessInfo.processInfo.environment
guard environment["GITHUB_ACTIONS"] == "true", environment["RUNNER_ENVIRONMENT"] == "github-hosted" else {
    fail("Display configuration is only allowed on GitHub-hosted runners.")
}
let display = CGMainDisplayID()
let modes = (CGDisplayCopyAllDisplayModes(display, nil) as? [CGDisplayMode]) ?? []
guard let mode = modes.first(where: { $0.width == 1920 && $0.height == 1080 }) else {
    fail("The runner has no 1920-by-1080 display mode.")
}
var configuration: CGDisplayConfigRef?
guard CGBeginDisplayConfiguration(&configuration) == .success else {
    fail("Cannot begin display configuration.")
}
guard CGConfigureDisplayWithDisplayMode(configuration, display, mode, nil) == .success else {
    CGCancelDisplayConfiguration(configuration)
    fail("Cannot select the display mode.")
}
guard CGCompleteDisplayConfiguration(configuration, .forSession) == .success else {
    fail("Cannot apply the display mode.")
}
guard let applied = CGDisplayCopyDisplayMode(display), applied.width == 1920, applied.height == 1080 else {
    fail("The runner did not apply the requested display mode.")
}
print("Hosted display mode: \(applied.width)x\(applied.height)")
