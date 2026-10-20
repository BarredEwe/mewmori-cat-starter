import AppKit
#if SWIFT_PACKAGE
import CatOCR
#else
import CatStarterCore
#endif
import SpriteKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var scene: CatScene!
    private var observationLabel: NSTextField!
    private var observationTimer: Timer?
    private var observationInProgress = false
    private var screenChangeDetector = ScreenChangeDetector()
    private let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")

    func applicationDidFinishLaunching(_ notification: Notification) {
        scene = CatScene(size: CGSize(width: 420, height: 360), isUITesting: isUITesting)
        let view = SKView(frame: NSRect(x: 0, y: 0, width: 420, height: 360))
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityIdentifier("cat-canvas")
        view.setAccessibilityLabel("Кот")
        view.presentScene(scene)
        scene.onCatPositionChange = { [weak view] x in
            view?.setAccessibilityValue(String(format: "%.1f", x))
        }

        let contentView = NSView(frame: view.bounds)
        view.autoresizingMask = [.width, .height]
        contentView.addSubview(view)

        observationLabel = NSTextField(labelWithString: "")
        observationLabel.alignment = .center
        observationLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        observationLabel.textColor = .white
        observationLabel.frame = NSRect(x: 12, y: 326, width: 396, height: 20)
        observationLabel.autoresizingMask = [.width, .minYMargin]
        observationLabel.setAccessibilityIdentifier("screen-observation")
        contentView.addSubview(observationLabel)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Cat Starter"
        window.center()
        window.contentView = contentView
        window.acceptsMouseMovedEvents = true
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        perform(#selector(observeScreen), with: nil, afterDelay: isUITesting ? 0.1 : 0.8)
        observationTimer = Timer.scheduledTimer(
            timeInterval: isUITesting ? 30 : 15,
            target: self,
            selector: #selector(observeScreen),
            userInfo: nil,
            repeats: true
        )
    }

    @MainActor @objc private func observeScreen() {
        guard !observationInProgress else { return }
        observationInProgress = true
        showObservation("Смотрю на экран…")

        if isUITesting,
           let text = ProcessInfo.processInfo.environment["CAT_STARTER_UI_TEST_OCR_TEXT"]
        {
            finishObservation(with: ScreenObservation.message(from: text))
            return
        }

        guard ScreenOCR.requestScreenCaptureAccess() else {
            finishObservation(with: "Разрешите Screen Recording и перезапустите кота.")
            return
        }

        let image: CGImage
        do {
            image = try ScreenOCR.captureMainDisplay()
            guard try screenChangeDetector.shouldRecognize(image) else {
                observationInProgress = false
                return
            }
        } catch {
            finishObservation(with: error.localizedDescription)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let message: String
            do {
                message = ScreenObservation.message(from: try ScreenOCR.recognizeText(in: image))
            } catch {
                message = error.localizedDescription
            }

            DispatchQueue.main.async {
                self?.finishObservation(with: message)
            }
        }
    }

    @MainActor private func finishObservation(with message: String) {
        observationInProgress = false
        showObservation(message)
    }

    @MainActor private func showObservation(_ message: String) {
        observationLabel.stringValue = message
        observationLabel.setAccessibilityLabel(message)
        observationLabel.setAccessibilityValue(message)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
