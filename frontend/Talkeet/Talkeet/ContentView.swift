/*
 * ContentView.swift
 *
 * Purpose: Top-level router between the drop zone (no file loaded) and
 *          the editor (file loaded).
 *
 * Responsibilities:
 *   - Show the drop zone + "Open File" button when no video is loaded.
 *   - Transition to EditorView once a file has been accepted.
 *   - Gate the drop zone / file picker on backend readiness.
 *   - Display backend status in the drop zone state.
 *
 * Constraints:
 *   - droppedFileURL / project state lives in ProjectViewModel (environment),
 *     not as local @State, so EditorView can observe the same instance.
 *   - File security scope is not required because App Sandbox is disabled.
 */

import OSLog
import SwiftUI

private let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "UI")

struct ContentView: View {
    @Environment(BackendManager.self) private var backend
    @Environment(ProjectViewModel.self) private var project
    @State private var isTargeted = false
    @State private var showingFilePicker = false

    var body: some View {
        if project.videoURL != nil {
            // File is loaded — show the full editor.
            EditorView(viewModel: project) {
                // "Close" resets the project so the drop zone is shown again.
                project.videoURL = nil
                project.player = nil
                project.segments = []
                project.errorMessage = nil
            }
        } else {
            dropZoneScreen
        }
    }

    // MARK: - Drop zone screen

    private var dropZoneScreen: some View {
        VStack(spacing: 24) {
            statusBar
            dropZone
            openFileButton
        }
        .padding(32)
        .frame(minWidth: 480, minHeight: 360)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.mpeg4Movie, .quickTimeMovie]
        ) { result in
            if case .success(let url) = result {
                log.info("File picked: \(url.lastPathComponent, privacy: .public)")
                project.loadFile(url)
            }
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(statusLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var statusColor: Color {
        switch backend.status {
        case .idle:      return .gray
        case .launching: return .yellow
        case .ready:     return .green
        case .error:     return .red
        }
    }

    private var statusLabel: String {
        switch backend.status {
        case .idle:             return "Idle"
        case .launching:        return "Starting…"
        case .ready:            return "Ready"
        case .error(let msg):   return "Error: \(msg)"
        }
    }

    // MARK: - Drop zone

    private var isReady: Bool {
        if case .ready = backend.status { return true }
        return false
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isTargeted ? Color.accentColor.opacity(0.06) : Color.clear)
                )

            VStack(spacing: 12) {
                Image(systemName: "film")
                    .font(.system(size: 44))
                    .foregroundStyle(isReady ? .secondary : .tertiary)

                Text("Drop an MP4 or MOV here")
                    .font(.headline)
                    .foregroundStyle(isReady ? .primary : .tertiary)
                Text(isReady ? "Drag a video file to begin" : "Waiting for backend…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
        }
        .opacity(isReady ? 1.0 : 0.5)
        .dropDestination(for: URL.self) { urls, _ in
            guard isReady else {
                log.debug("File drop ignored — backend not ready")
                return false
            }
            let accepted = urls.first {
                ["mp4", "mov"].contains($0.pathExtension.lowercased())
            }
            guard let url = accepted else {
                let exts = urls.map { $0.pathExtension }.joined(separator: ", ")
                log.info("File drop rejected — unsupported extension(s): \(exts, privacy: .public)")
                return false
            }
            log.info("File accepted: \(url.lastPathComponent, privacy: .public)")
            project.loadFile(url)
            return true
        } isTargeted: { targeted in
            isTargeted = isReady && targeted
        }
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .animation(.easeInOut(duration: 0.2), value: isReady)
    }

    // MARK: - Open File button

    private var openFileButton: some View {
        Button("Open File…") {
            showingFilePicker = true
        }
        .disabled(!isReady)
        .keyboardShortcut("o", modifiers: .command)
    }
}

#Preview {
    ContentView()
        .environment(BackendManager())
        .environment(ProjectViewModel())
}
