/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreVideo
import FBControlCore
import FBSimulatorControl
import Foundation

/// A JSON command received on stdin.
struct StdinCommand: Decodable {
  let method: String
  let params: Params?

  struct Params: Decodable {
    let overlays: [OverlayShape]?
    let index: Int?
    let text: String?
    let position: String?
    let content: String?
    let fit: Bool?
  }
}

/// Handles fire-and-forget JSON commands from stdin for the video-stream subcommand.
///
/// Commands are one JSON object per line. No responses are sent — stdin is a one-way pipe.
/// stdout is unused (or available for video data). stderr carries logs.
@MainActor
public final class StdinCommandHandler {
  public let renderer: OverlayRenderer
  let screenshotDir: String?
  let logger: FBControlCoreLogger

  public private(set) var shutdownRequested = false
  private var shutdownContinuation: CheckedContinuation<Void, Never>?

  /// Weak reference to the video stream for overlay updates and timed metadata.
  /// Set by the caller after stream creation.
  public weak var videoStream: SimulatorVideoStream?

  public init(
    renderer: OverlayRenderer,
    screenshotDir: String?,
    logger: FBControlCoreLogger
  ) {
    self.renderer = renderer
    self.screenshotDir = screenshotDir
    self.logger = logger
  }

  /// Process a single JSON line from stdin. Async so command effects on the video-stream actor are
  /// awaited, preserving strict per-line ordering (a screenshot observes every prior overlay update).
  public func handleLine(_ line: String) async {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    guard let data = trimmed.data(using: .utf8) else { return }

    let command: StdinCommand
    do {
      command = try JSONDecoder().decode(StdinCommand.self, from: data)
    } catch {
      logger.log("Failed to decode stdin command: \(error)")
      return
    }

    switch command.method {
    case "overlay":
      await handleOverlay(command.params?.overlays ?? [])
    case "screenshot":
      await handleScreenshot(index: command.params?.index ?? 0)
    case "chapter":
      await handleChapter(command.params?.text)
    case "bar":
      await handleBar(command.params)
    case "bottomStatus":
      logger.log("bottomStatus is deprecated; use {method:\"bar\", params:{position:\"bottom\", ...}}")
      await handleBar(position: "bottom", content: command.params?.text == nil ? nil : "text", text: command.params?.text, fit: nil)
    case "topStatus":
      logger.log("topStatus is deprecated; use {method:\"bar\", params:{position:\"top\", ...}}")
      await handleBar(position: "top", content: command.params?.text == nil ? nil : "text", text: command.params?.text, fit: nil)
    case "force_keyframe":
      handleForceKeyframe()
    case "shutdown":
      handleShutdown()
    default:
      logger.log("Unknown stdin command: \(command.method)")
    }
  }

  /// `{"method":"force_keyframe"}` — the next encoded frame is an IDR. A consumer that has just
  /// joined a stream (or lost frames) can decode immediately instead of waiting for the next
  /// periodic keyframe; the same command the WebRTC streamer accepts, so callers need one spelling.
  private func handleForceKeyframe() {
    guard let videoStream else {
      logger.log("force_keyframe requested but no video stream available")
      return
    }
    videoStream.requestKeyFrame()
    logger.log("Forwarded force_keyframe to video stream")
  }

  /// Wait for a shutdown command. Returns when "shutdown" is received or stdin closes.
  public func waitForShutdown() async {
    if shutdownRequested { return }
    await withCheckedContinuation { continuation in
      self.shutdownContinuation = continuation
    }
  }

  // MARK: - Command Handlers

  private func handleOverlay(_ overlays: [OverlayShape]) async {
    if overlays.isEmpty {
      renderer.clear()
      // Re-render bars if any are active, since clear() wipes the buffer.
      let hasBarContent = renderer.barContent.values.contains(where: { $0 != .hidden })
      if hasBarContent {
        renderer.renderToBuffer()
        await updateStreamOverlay(renderer.buffer)
      } else {
        await updateStreamOverlay(nil)
      }
      logger.log("Overlay cleared")
    } else {
      renderer.render(overlays: overlays)
      await updateStreamOverlay(renderer.buffer)
      logger.log("Overlay updated with \(overlays.count) shapes")

      // Start effect timer if any shapes have animations. The refresh is fire-and-forget: animation
      // frames have no ordering contract with stdin commands.
      renderer.startEffectTimer { [weak self] in
        Task { [weak self] in
          await self?.updateStreamOverlay(self?.renderer.buffer)
        }
      }
    }
  }

  /// Push the renderer's buffer to the video-stream actor.
  private func updateStreamOverlay(_ buffer: CVPixelBuffer?) async {
    guard let videoStream else { return }
    // The overlay CVPixelBuffer is produced by the renderer and only read by the stream's
    // compositor; the renderer serializes its own mutations.
    // patternlint-disable-next-line swift-nonisolated-unsafe
    nonisolated(unsafe) let buffer = buffer
    await videoStream.updateOverlayBuffer(buffer)
  }

  private func handleScreenshot(index: Int) async {
    guard let dir = screenshotDir else {
      logger.log("Screenshot requested but no --screenshot-dir configured")
      return
    }
    guard let videoStream else {
      logger.log("Screenshot requested but no video stream available")
      return
    }

    let tmpPath = (dir as NSString).appendingPathComponent("screenshot_\(index).tmp.png")
    let finalPath = (dir as NSString).appendingPathComponent("screenshot_\(index).png")

    logger.log("Screenshot \(index) requested (writing to \(finalPath))")

    let pngData: Data
    do {
      pngData = try await videoStream.captureCompositedScreenshot()
    } catch {
      logger.log("Screenshot \(index) failed: \(error.localizedDescription)")
      return
    }

    // Atomic rename: write to .tmp first, then rename.
    if FileManager.default.fileExists(atPath: tmpPath) {
      try? FileManager.default.removeItem(atPath: tmpPath)
    }
    guard FileManager.default.createFile(atPath: tmpPath, contents: pngData) else {
      logger.log("Screenshot \(index) failed: could not create file at \(tmpPath)")
      return
    }
    guard rename(tmpPath, finalPath) == 0 else {
      logger.log("Screenshot \(index) failed: could not rename \(tmpPath) to \(finalPath) (errno=\(errno))")
      return
    }
    logger.log("Screenshot \(index) written to \(finalPath) (\(pngData.count) bytes)")
  }

  private func handleBar(_ params: StdinCommand.Params?) async {
    guard let position = params?.position else {
      logger.log("bar command missing position")
      return
    }
    await handleBar(position: position, content: params?.content, text: params?.text, fit: params?.fit)
  }

  private func handleBar(position: String, content: String?, text: String?, fit: Bool?) async {
    let barContent: BarContent
    switch content {
    case "text":
      barContent = .text(text ?? "")
    case "stats":
      barContent = .stats
    case nil, .some(""):
      barContent = .hidden
    case .some(let unknown):
      logger.log("bar command unknown content type: \(unknown)")
      return
    }
    // `fit` is a per-bar setting: when provided it overrides; when omitted the previous value is
    // retained. It applies to whatever the bar currently displays (text or stats) so callers can
    // set it once and have subsequent stats updates inherit the shrink-to-fit behaviour.
    if let fit {
      renderer.setBarFit(fit, position: position)
    }
    renderer.setBarContent(barContent, position: position)
    await updateStreamOverlay(renderer.buffer)
    logger.log("bar \(position) set to \(barContent) (fit=\(renderer.barFit[position] ?? false))")
  }

  private func handleChapter(_ text: String?) async {
    guard let text, !text.isEmpty else {
      logger.log("Chapter command missing text")
      return
    }
    guard let videoStream else {
      logger.log("Chapter command received but no video stream available")
      return
    }
    await videoStream.writeTimedMetadata(text)
    logger.log("Chapter marker emitted: \(text)")
  }

  private func handleShutdown() {
    logger.log("Shutdown requested via stdin")
    shutdownRequested = true
    shutdownContinuation?.resume()
    shutdownContinuation = nil
  }
}

// MARK: - Signal-driven stdin loop

extension StdinCommandHandler {

  /// Drive this handler's stdin command loop until it ends (stdin EOF or a `shutdown` command) or a
  /// termination signal (SIGINT/SIGTERM) arrives — whichever comes first — then return so the caller
  /// can finalize recording/streaming. Mirrors
  /// `FBLaunchedApplication.waitForAppToExitOrSignal`: the signal/lifecycle handling lives in the layer
  /// the command calls, so `video-stream`/`record` stay signal-agnostic.
  ///
  /// Uses `stdinLines`, whose read ends on cancellation, so a signal genuinely stops the loop instead
  /// of wedging on an uninterruptible read. Both task-group children are non-isolated (matching
  /// `waitForAppToExitOrSignal`), hopping to the main actor only to touch this `@MainActor` handler —
  /// the Swift 6 region checker rejects an actor-isolated child task in the group.
  public nonisolated func driveUntilStoppedOrSignal(waitForSignal: @escaping @Sendable () async -> Void) async {
    await withTaskGroup(of: Void.self) { group in
      group.addTask {
        for await line in stdinLines() {
          await self.handleLine(line)
          if await self.shutdownRequested { break }
        }
        // Natural end (EOF / `shutdown`): synthesize a shutdown so the handler stops the stream
        // cleanly. On cancellation (a signal won the race) skip it — the caller finalizes directly.
        if !Task.isCancelled {
          if await !self.shutdownRequested {
            await self.handleLine("{\"method\":\"shutdown\"}")
          }
        }
      }
      group.addTask { await waitForSignal() }
      _ = await group.next()
      group.cancelAll()
    }
  }
}
