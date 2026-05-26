/*
 * TalkeetApp.swift
 *
 * Purpose: Application entry point. Owns BackendManager and ProjectViewModel
 *          and drives their lifecycles from the SwiftUI scene phase.
 *
 * Responsibilities:
 *   - Instantiate BackendManager and ProjectViewModel as @State for full app lifetime.
 *   - Inject both into the environment for all descendant views.
 *   - Start/stop the backend with the scene phase.
 *
 * Constraints:
 *   - Backend starts on .active (not on init) to avoid a race with window appearing.
 *   - Backend stops on .background only — .inactive fires on focus loss, not quit.
 *   - On macOS, Cmd+Q exits before scenePhase reaches .background, so
 *     NSApplication.willTerminateNotification is also observed as a safety net.
 */

import AppKit
import OSLog
import SwiftUI

private let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "App")

@main
struct TalkeetApp: App {
    @State private var backend = BackendManager()
    @State private var project = ProjectViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup("Talkeet") {
            ContentView()
                .environment(backend)
                .environment(project)
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.willTerminateNotification)
                ) { _ in
                    log.info("App will terminate — stopping backend")
                    backend.stop()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                log.info("Scene became active — starting backend")
                backend.start()
            case .background:
                log.info("Scene moved to background — stopping backend")
                backend.stop()
            default:
                break
            }
        }
    }
}
