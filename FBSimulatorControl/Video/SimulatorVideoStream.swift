/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreMedia
import CoreVideo
import FBControlCore
import Foundation
import IOSurface
import VideoToolbox

enum SimulatorVideoStreamError: Error {
  case startWhenStopped
  case startAlreadyStarted
  case stopWithoutConsumer
  case failedToTearDownFramePusher(errorDescription: String)
  case failedToCreatePixelBufferFromSurface(status: CVReturn)
  case failedToCreatePixelBufferFromSurfaceNil
  case mountSurfaceWithoutConsumer
  case noPixelBufferForScreenshot
}

extension SimulatorVideoStreamError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .startWhenStopped:
      return "Cannot start streaming, since streaming is stopped"
    case .startAlreadyStarted:
      return "Cannot start streaming, since streaming has already has started"
    case .stopWithoutConsumer:
      return "Cannot stop streaming, no consumer attached"
    case .failedToTearDownFramePusher(let errorDescription):
      return "Failed to tear down frame pusher: \(errorDescription)"
    case .failedToCreatePixelBufferFromSurface(let status):
      return "Failed to create Pixel Buffer from Surface with errorCode \(status)"
    case .failedToCreatePixelBufferFromSurfaceNil:
      return "Failed to create Pixel Buffer from Surface (nil)"
    case .mountSurfaceWithoutConsumer:
      return "Cannot mount surface when there is no consumer"
    case .noPixelBufferForScreenshot:
      return "No pixel buffer available for screenshot"
    }
  }
}

// MARK: - Value Types

/// Edge insets that extend the output frame dimensions beyond the source framebuffer.
/// Each edge adds opaque pixels for overlay content (label bars, diagnostic stats, etc.).
public struct VideoStreamEdgeInsets: Sendable {
  public var top: UInt
  public var bottom: UInt
  public var left: UInt
  public var right: UInt

  public init(top: UInt, bottom: UInt, left: UInt, right: UInt) {
    self.top = top
    self.bottom = bottom
    self.left = left
    self.right = right
  }
}

/// Frame cadence strategy for the video stream.
///
/// - `.lazy`: variable-frame-rate — a frame is pushed only when the framebuffer signals that a new
///   frame was rendered (a `.frameRendered` event).
/// - `.eager(framesPerSecond:)`: constant-frame-rate — a cadence `Task` pushes frames at the fixed
///   rate, and frame-rendered events are ignored (the cadence task drives pushes).
enum VideoStreamCadence {
  case lazy
  case eager(framesPerSecond: UInt)
}

private extension VideoStreamCodec {
  var videoToolboxCodec: CMVideoCodecType {
    switch self {
    case .h264:
      return kCMVideoCodecType_H264
    case .hevc:
      return kCMVideoCodecType_HEVC
    }
  }
}

private func bitmapStreamPixelBufferAttributes(from pixelBuffer: CVPixelBuffer) -> [String: Any] {
  let width = CVPixelBufferGetWidth(pixelBuffer)
  let height = CVPixelBufferGetHeight(pixelBuffer)
  let frameSize = CVPixelBufferGetDataSize(pixelBuffer)
  let rowSize = CVPixelBufferGetBytesPerRow(pixelBuffer)
  let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
  let pixelFormatString = pixelFormat.fourCharCodeString

  var columnLeft = 0
  var columnRight = 0
  var rowsTop = 0
  var rowsBottom = 0
  CVPixelBufferGetExtendedPixels(pixelBuffer, &columnLeft, &columnRight, &rowsTop, &rowsBottom)

  return [
    "width": width,
    "height": height,
    "row_size": rowSize,
    "frame_size": frameSize,
    "padding_column_left": columnLeft,
    "padding_column_right": columnRight,
    "padding_row_top": rowsTop,
    "padding_row_bottom": rowsBottom,
    "format": pixelFormatString,
  ]
}

/// A real-time video stream of a Simulator's framebuffer, written to an `DataConsumer`.
///
/// Concurrency model: the actor serializes start/stop, framebuffer event handling, and every frame
/// push. Framebuffer events arrive on the attachment's ordered `AsyncStream`, consumed by an
/// actor-isolated task, rather than queue-delivered callbacks. The cadence is selected by the
/// `cadence` strategy: `.lazy` pushes a frame when a frame-rendered event pokes the trigger stream
/// (variable frame rate), while `.eager` runs a cadence `Task` on the actor that pushes at a fixed frame rate.
public actor SimulatorVideoStream: VideoStreamOperation {

  // MARK: - Properties

  let framebuffer: Framebuffer
  let configuration: VideoStreamConfiguration
  let edgeInsets: VideoStreamEdgeInsets
  let cadence: VideoStreamCadence
  /// When set (recording), encoded `.compressed` frames are routed to this sink — an `SimulatorVideoFileWriter`
  /// — instead of being byte-framed to `consumer`. nil for streaming.
  let encodedSampleConsumerOverride: EncodedSampleConsumer?
  let logger: any ControlCoreLogger

  // MARK: - Lifecycle

  /// What a started stream holds: the consumer, the framebuffer attachment (whose `cancel()`
  /// detaches this stream), and the task consuming the attachment's ordered event stream onto the
  /// actor (surface changes mount, frame-rendered events poke the `.lazy` trigger; it ends when the
  /// attachment cancels, finishing the stream).
  /// Sendable so the nonisolated `deinit` backstop can reach the attachment and event task.
  private struct Session: Sendable {
    // SAFETY: DataConsumer is a thread-safe ObjC protocol that predates Sendable auditing — the
    // `startStreaming` shim already carries it across the boundary on the same justification.
    // patternlint-disable-next-line swift-nonisolated-unsafe
    nonisolated(unsafe) let consumer: any DataConsumer
    let attachment: FramebufferAttachment
    let eventTask: Task<Void, Never>
  }

  /// One-way: `.idle` → `.starting` → `.streaming` → `.stopped`. A stop is legal from `.starting`; a
  /// failed initial mount unwinds `.starting` back to `.idle`.
  private enum Lifecycle: Sendable {
    /// Never started; a `startStreaming` may begin.
    case idle
    /// Attached, awaiting the first surface mount; the awaiters are suspended `startStreaming` callers.
    case starting(Session, startAwaiters: [CheckedContinuation<Void, Error>])
    /// The first surface mounted; frames flow.
    case streaming(Session)
    /// Terminal; the stream cannot be restarted.
    case stopped
  }

  private var lifecycle: Lifecycle = .idle

  /// Completion awaiters, keyed per await so a cancelled `awaitCompletion` can resume its own
  /// continuation even when the stream cannot be stopped. Kept outside `Lifecycle` because
  /// completion can be awaited in any phase, including before a start.
  private var stopAwaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

  /// The push-loop task that drives frame pushes (nil before `mountSurface` starts it). It iterates a
  /// stimulus `AsyncSequence` of `FrameTrigger`s: `FrameCadence` (the fixed-rate clock) in `.eager`
  /// mode, or `LazyFrameTriggers` (poked by the framebuffer callbacks) in `.lazy` mode.
  /// Started in `mountSurface`, cancelled in `cadenceTeardown`/`deinit`.
  private var framePusherTask: Task<Void, Never>?

  /// In `.lazy` (VFR) mode, the trigger source that the framebuffer event loop (`.frameRendered`)
  /// and `updateOverlayBuffer` poke to drive a push through the shared loop. Created in `mountSurface`,
  /// finished in `cadenceTeardown`. Nil in `.eager` mode (the cadence clock drives pushes there).
  private var lazyTriggers: LazyFrameTriggers?

  var pixelBuffer: CVPixelBuffer?
  var timeAtFirstFrame: CFTimeInterval = 0
  var timeAtLastPush: CFTimeInterval = 0
  var frameNumber: UInt = 0
  var pixelBufferAttributes: [String: Any]?
  /// The session's consumer while started, nil otherwise — the mount and push paths read this.
  var consumer: (any DataConsumer)? {
    switch lifecycle {
    case .idle, .stopped:
      return nil
    case .starting(let session, _), .streaming(let session):
      return session.consumer
    }
  }
  var framePusher: (any FramePusher)?
  /// The transport writers for compressed video, created on the first mount and shared by every
  /// pusher the stream creates: they carry per-stream state (MPEG-TS continuity counters, the fMP4
  /// init segment and sequence numbers) that must survive a surface swap. nil for other formats.
  var frameWriters: VideoStreamFrameWriters?
  /// The timed-metadata (chapter) sink: the streaming transport writer, or (recording) the file
  /// writer's chapter track. Resolved in `mountSurface`, cleared in `stopStreaming`.
  var timedMetadataConsumer: (any TimedMetadataConsumer)?

  /// Overlay and edge-inset compositing; configured for the source at every mount.
  let compositor: OverlayCompositor

  // MARK: - Initializers

  /// Makes a stream with no edge insets. Cadence is derived from `configuration.framesPerSecond`.
  public static func make(framebuffer: Framebuffer, configuration: VideoStreamConfiguration, logger: any ControlCoreLogger) -> SimulatorVideoStream {
    make(framebuffer: framebuffer, configuration: configuration, edgeInsets: VideoStreamEdgeInsets(top: 0, bottom: 0, left: 0, right: 0), logger: logger)
  }

  /// Makes a stream whose output frame is extended by `edgeInsets` (reserved for overlay content).
  public static func make(framebuffer: Framebuffer, configuration: VideoStreamConfiguration, edgeInsets: VideoStreamEdgeInsets, logger: any ControlCoreLogger) -> SimulatorVideoStream {
    SimulatorVideoStream(
      framebuffer: framebuffer,
      configuration: configuration,
      edgeInsets: edgeInsets,
      cadence: cadence(for: configuration),
      logger: logger)
  }

  /// Constructs a recording stream: encoded `.compressed` frames are muxed into a file via `fileWriter`
  /// rather than byte-framed to an `DataConsumer`. `edgeInsets` (default zero) reserves overlay bar
  /// regions exactly as on the streaming path. Cadence is derived from `configuration.framesPerSecond`.
  static func makeRecorder(framebuffer: Framebuffer, configuration: VideoStreamConfiguration, edgeInsets: VideoStreamEdgeInsets = VideoStreamEdgeInsets(top: 0, bottom: 0, left: 0, right: 0), fileWriter: SimulatorVideoFileWriter, logger: any ControlCoreLogger) -> SimulatorVideoStream {
    return SimulatorVideoStream(
      framebuffer: framebuffer,
      configuration: configuration,
      edgeInsets: edgeInsets,
      cadence: cadence(for: configuration),
      logger: logger,
      encodedSampleConsumerOverride: fileWriter)
  }

  /// Makes and starts a stream to `consumer`.
  public static func start(framebuffer: Framebuffer, configuration: VideoStreamConfiguration, edgeInsets: VideoStreamEdgeInsets = VideoStreamEdgeInsets(top: 0, bottom: 0, left: 0, right: 0), to consumer: any DataConsumer, logger: any ControlCoreLogger) async throws -> SimulatorVideoStream {
    let stream = make(framebuffer: framebuffer, configuration: configuration, edgeInsets: edgeInsets, logger: logger)
    try await stream.startStreaming(consumer)
    return stream
  }

  /// Eager (constant-frame-rate) when a positive `framesPerSecond` is set, else lazy (variable-rate,
  /// driven by damage events).
  private static func cadence(for configuration: VideoStreamConfiguration) -> VideoStreamCadence {
    guard let framesPerSecond = configuration.framesPerSecond, framesPerSecond > 0 else {
      return .lazy
    }
    return .eager(framesPerSecond: UInt(framesPerSecond))
  }

  init(framebuffer: Framebuffer, configuration: VideoStreamConfiguration, edgeInsets: VideoStreamEdgeInsets, cadence: VideoStreamCadence, logger: any ControlCoreLogger, encodedSampleConsumerOverride: EncodedSampleConsumer? = nil) {
    self.framebuffer = framebuffer
    self.configuration = configuration
    self.edgeInsets = edgeInsets
    self.cadence = cadence
    self.encodedSampleConsumerOverride = encodedSampleConsumerOverride
    self.logger = logger
    self.compositor = OverlayCompositor(edgeInsets: edgeInsets)
  }

  deinit {
    // Backstop teardown if the stream is dropped without a clean stopStreaming: cancel the
    // attachment (finishing the event stream, which ends the event task) and both tasks.
    // Reachable while the push loop runs because it holds the stream weakly; that loop also exits
    // on its own at the next trigger once the stream is gone. A `.starting` phase with pending
    // awaiters cannot reach deinit — a suspended caller keeps the actor alive.
    switch lifecycle {
    case .starting(let session, _), .streaming(let session):
      session.attachment.cancel()
      session.eventTask.cancel()
    case .idle, .stopped:
      break
    }
    framePusherTask?.cancel()
  }

  // MARK: - Public

  public nonisolated func startStreaming(_ consumer: any DataConsumer) async throws {
    // DataConsumer is a thread-safe ObjC protocol that isn't Sendable; this single shim carries it
    // onto the actor, where it is confined thereafter.
    // patternlint-disable-next-line swift-nonisolated-unsafe
    nonisolated(unsafe) let consumer = consumer
    try await isolatedStartStreaming(consumer)
  }

  private func isolatedStartStreaming(_ consumer: any DataConsumer) async throws {
    switch lifecycle {
    case .starting, .streaming:
      throw SimulatorVideoStreamError.startAlreadyStarted
    case .stopped:
      throw SimulatorVideoStreamError.startWhenStopped
    case .idle:
      break
    }
    let attachment = try framebuffer.attach()
    // Consume the attachment's ordered event stream onto the actor. `[weak self]` so the task
    // never keeps the stream alive; the strong `attachment` capture ends when the stream
    // finishes (attachment cancel), completing the loop.
    let eventTask = Task { [weak self] in
      for await event in attachment.events {
        await self?.handle(event)
      }
    }
    lifecycle = .starting(Session(consumer: consumer, attachment: attachment, eventTask: eventTask), startAwaiters: [])
    // When a surface is already available this mounts it synchronously (transitioning to
    // `.streaming`), otherwise the first surface event does.
    if let surface = attachment.initialSurface {
      do {
        try mountSurface(surface)
      } catch {
        // No awaiters exist yet, so this only tears the session down; the error is thrown to the caller.
        failPendingStart(with: error)
        throw error
      }
      pushFrame(forceKeyFrame: false)
    }
    guard case .starting = lifecycle else {
      return // mounted synchronously — already streaming
    }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      guard case .starting(let session, var awaiters) = lifecycle else {
        continuation.resume()
        return
      }
      awaiters.append(continuation)
      lifecycle = .starting(session, startAwaiters: awaiters)
    }
  }

  public func stopStreaming() async throws {
    let session: Session
    let pendingStartAwaiters: [CheckedContinuation<Void, Error>]
    switch lifecycle {
    case .stopped:
      return
    case .idle:
      throw SimulatorVideoStreamError.stopWithoutConsumer
    case .starting(let active, let awaiters):
      session = active
      pendingStartAwaiters = awaiters
    case .streaming(let active):
      session = active
      pendingStartAwaiters = []
    }
    // Transition first so a failing pusher teardown still leaves the stream `.stopped` with awaiters resumed.
    lifecycle = .stopped
    session.attachment.cancel()
    session.eventTask.cancel()
    session.consumer.consumeEndOfFile()
    var tearDownError: Error?
    if let framePusher {
      do {
        try framePusher.tearDown()
      } catch {
        tearDownError = error
      }
    }
    timedMetadataConsumer = nil
    frameWriters = nil
    compositor.reset()
    cadenceTeardown()
    resumeStopAwaiters()
    for awaiter in pendingStartAwaiters {
      awaiter.resume(throwing: SimulatorVideoStreamError.startWhenStopped)
    }
    if let tearDownError {
      throw SimulatorVideoStreamError.failedToTearDownFramePusher(errorDescription: "\(tearDownError)")
    }
  }

  /// Resume everyone awaiting completion.
  private func resumeStopAwaiters() {
    let awaiters = stopAwaiters
    stopAwaiters = [:]
    for awaiter in awaiters.values {
      awaiter.resume()
    }
  }

  /// Unwind a start still awaiting its first mount because that mount failed: the awaiters are
  /// failed and the session is torn down (back to `.idle`), so a stream that reported a failed
  /// start can never quietly self-start on a later surface. A no-op once `.streaming` — a failed
  /// mid-stream surface swap keeps streaming the previous surface.
  private func failPendingStart(with error: Error) {
    guard case .starting(let session, let awaiters) = lifecycle else {
      return
    }
    lifecycle = .idle
    session.eventTask.cancel()
    session.attachment.cancel()
    for awaiter in awaiters {
      awaiter.resume(throwing: error)
    }
  }

  /// Finishes the `.lazy` trigger stream and cancels the push-loop task (cancellation also wakes an
  /// `.eager` loop suspended in `Task.sleep`).
  func cadenceTeardown() {
    lazyTriggers?.finish()
    lazyTriggers = nil
    framePusherTask?.cancel()
    framePusherTask = nil
  }

  // MARK: - Framebuffer Events

  /// Apply a single framebuffer event. Per-event work is O(1) and non-suspending, honoring the
  /// unbounded event stream's drain invariant: a surface change (always a genuinely different surface,
  /// `Framebuffer` drops re-reports) mounts once; a rendered frame pokes
  /// the `.lazy` trigger, whose `bufferingNewest(1)` coalescing keeps real-time frame dropping where
  /// it belongs. In `.eager` mode the cadence clock drives pushes, so frame-rendered events are ignored.
  private func handle(_ event: FramebufferEvent) {
    switch event {
    case let .surfaceChanged(surface):
      guard let surface else { return }
      do {
        try mountSurface(surface)
      } catch {
        logger.log("Failed to mount incoming surface: \(error)")
        failPendingStart(with: error)
        return
      }
      pushFrame(forceKeyFrame: false)
    case .frameRendered:
      switch cadence {
      case .lazy:
        lazyTriggers?.signalFrameRendered()
      case .eager:
        break
      }
    }
  }

  // MARK: - Private (Surface)

  func mountSurface(_ surface: IOSurface) throws {
    // CVPixelBufferCreateWithIOSurface returns +1 via an Unmanaged out-param; takeRetainedValue() adopts it.
    var unmanagedBuffer: Unmanaged<CVPixelBuffer>?
    let status = CVPixelBufferCreateWithIOSurface(nil, surface, nil, &unmanagedBuffer)
    if status != kCVReturnSuccess {
      throw SimulatorVideoStreamError.failedToCreatePixelBufferFromSurface(status: status)
    }
    guard let buffer = unmanagedBuffer?.takeRetainedValue() else {
      throw SimulatorVideoStreamError.failedToCreatePixelBufferFromSurfaceNil
    }

    guard let consumer else {
      throw SimulatorVideoStreamError.mountSurfaceWithoutConsumer
    }

    let attributes = bitmapStreamPixelBufferAttributes(from: buffer)
    logger.log("Mounting Surface \(IOSurfaceGetID(surface)) with Attributes: \(CollectionInformation.oneLineDescription(from: attributes))")

    if frameWriters == nil, case let .compressedVideo(codec, transport) = configuration.format {
      frameWriters = transport.frameWriters(for: codec)
    }
    let framePusher = try Self.framePusher(
      configuration: configuration,
      cadence: cadence,
      consumer: consumer,
      encodedSampleConsumerOverride: encodedSampleConsumerOverride,
      frameWriters: frameWriters,
      logger: logger)
    try framePusher.setup(with: buffer, edgeInsets: edgeInsets)

    // Published only once every throwing step is past, so a mount is all-or-nothing: a failed one
    // leaves the previous surface installed rather than a new `pixelBuffer` behind a pusher never
    // set up for it.
    let previousFramePusher = self.framePusher
    self.pixelBuffer = buffer
    self.pixelBufferAttributes = attributes
    self.framePusher = framePusher
    // The displaced pusher's VideoToolbox sessions are only released deterministically by
    // `tearDown`; releasing the reference alone can leave them alive with encodes in flight into
    // the same consumer. Torn down after the new pusher is published so a swap never leaves the
    // stream without a working pusher, and a teardown failure cannot fail an otherwise good mount.
    if let previousFramePusher {
      do {
        try previousFramePusher.tearDown()
        logger.log("Tore down the previous frame pusher after a surface swap")
      } catch {
        logger.log("Failed to tear down the previous frame pusher after a surface swap: \(error)")
      }
    }
    // Resolve the timed-metadata (chapter) sink. A recording file writer that supports chapters
    // supplies its own consumer; otherwise the streaming transport writer (fMP4 emsg / MPEG-TS ID3)
    // handles markers, dropping them on transports with no metadata channel.
    if let recordingMetadata = encodedSampleConsumerOverride as? TimedMetadataConsumer {
      self.timedMetadataConsumer = recordingMetadata
    } else if case .compressedVideo = configuration.format {
      self.timedMetadataConsumer = TransportTimedMetadataConsumer(consumer: consumer, timedMetadataWriter: frameWriters?.timedMetadataWriter)
    }

    compositor.configure(
      sourceWidth: CVPixelBufferGetWidth(buffer), sourceHeight: CVPixelBufferGetHeight(buffer), scaleFactor: configuration.scaleFactor)
    let insets = edgeInsets
    if insets.top + insets.bottom + insets.left + insets.right > 0 {
      logger.info().log("Composited pool includes edge insets (t=\(insets.top) b=\(insets.bottom) l=\(insets.left) r=\(insets.right)): w=\(compositor.outputWidth)/h=\(compositor.outputHeight)")
    }

    // The first mount transitions `.starting` → `.streaming`, resuming anyone awaiting it. A
    // re-mount (surface swap) is already `.streaming` and transitions nothing.
    if case .starting(let session, let awaiters) = lifecycle {
      lifecycle = .streaming(session)
      for awaiter in awaiters {
        awaiter.resume()
      }
    }

    // Started once; a surface re-mount just swaps `pixelBuffer` for the running loop. The task holds the
    // stream weakly: a strong capture would make task and actor keep each other alive, so a stream dropped
    // without `stopStreaming` would push forever and `deinit` could never run.
    guard framePusherTask == nil else { return }
    switch cadence {
    case let .eager(framesPerSecond):
      framePusherTask = Task { [weak self, logger] in
        let stats = CadenceStats(frameIntervalNanos: NSEC_PER_SEC / UInt64(framesPerSecond), logger: logger)
        await Self.runFramePushLoop(stimulus: FrameCadence(framesPerSecond: framesPerSecond), stats: stats) { self }
      }
    case .lazy:
      let triggers = LazyFrameTriggers()
      lazyTriggers = triggers
      framePusherTask = Task { [weak self] in
        await Self.runFramePushLoop(stimulus: triggers, stats: nil) { self }
      }
    }
  }

  func pushFrame(forceKeyFrame: Bool) {
    guard let pixelBuffer, let consumer, let framePusher else {
      return
    }
    if !consumer.hasCapacityForFrame(logger: logger) {
      return
    }

    // Uptime is monotonic; the wall clock steps under NTP and can hand the encoder (and a file
    // writer) a timestamp earlier than the previous frame's.
    let now = ProcessInfo.processInfo.systemUptime
    let frameNumber = self.frameNumber
    if frameNumber == 0 {
      timeAtFirstFrame = now
    }
    let timeAtFirstFrame = self.timeAtFirstFrame
    let frameDuration = timeAtLastPush > 0 ? (now - timeAtLastPush) : 0
    timeAtLastPush = now

    // The simulator's render server writes into the mounted surface; the lock is advisory, so the
    // seed is compared across the read to count frames it wrote into anyway. Every read of the
    // source happens inside this window — the overlay composite and the pusher's colour conversion —
    // and nothing after it touches the source.
    let sourceSurface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
    let seedBefore = sourceSurface.map { IOSurfaceGetSeed($0) }
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)

    do {
      try framePusher.writeEncodedFrame(
        compositor.composite(pixelBuffer),
        frameNumber: frameNumber,
        timeAtFirstFrame: timeAtFirstFrame,
        frameDuration: frameDuration,
        forceKeyFrame: forceKeyFrame)
    } catch {
      logger.log("Failed to submit frame \(frameNumber) for encoding: \(error)")
    }

    CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
    if let sourceSurface, let seedBefore, IOSurfaceGetSeed(sourceSurface) != seedBefore {
      framePusher.recordTornFrame()
    }

    self.frameNumber = frameNumber + 1
  }

  // MARK: - Frame Pusher

  static func framePusher(
    configuration: VideoStreamConfiguration,
    cadence: VideoStreamCadence,
    consumer: any DataConsumer,
    encodedSampleConsumerOverride: EncodedSampleConsumer?,
    frameWriters: VideoStreamFrameWriters?,
    logger: any ControlCoreLogger
  ) throws -> any FramePusher {
    let settings = VideoToolboxEncoderSettings(
      configuration: configuration, cadence: cadence, sink: encodedSampleConsumerOverride == nil ? .live : .file)
    switch configuration.format {
    case let .compressedVideo(codec, transport):
      let frameWriters = frameWriters ?? transport.frameWriters(for: codec)
      return VideoToolboxFramePusher(
        settings: settings, scaleFactor: configuration.scaleFactor, videoCodec: codec.videoToolboxCodec,
        encodedSampleConsumer: encodedSampleConsumerOverride
          ?? DataConsumerEncodedSampleConsumer(consumer: consumer, frameWriter: frameWriters.frameWriter, timedMetadataWriter: frameWriters.timedMetadataWriter),
        logger: logger)
    case .mjpeg:
      return VideoToolboxFramePusher(
        settings: settings, scaleFactor: configuration.scaleFactor, videoCodec: kCMVideoCodecType_JPEG,
        encodedSampleConsumer: encodedSampleConsumerOverride ?? MJPEGSampleConsumer(consumer: consumer),
        logger: logger)
    case .minicap:
      return VideoToolboxFramePusher(
        settings: settings, scaleFactor: configuration.scaleFactor, videoCodec: kCMVideoCodecType_JPEG,
        encodedSampleConsumer: encodedSampleConsumerOverride ?? MinicapSampleConsumer(consumer: consumer),
        logger: logger)
    case .bgra:
      return BitmapFramePusher(consumer: consumer, scaleFactor: configuration.scaleFactor)
    }
  }

  /// Write a timed metadata marker (chapter) at the current stream position. Routed to the
  /// `TimedMetadataConsumer` resolved in `mountSurface` — the streaming transport writer
  /// (MPEG-TS ID3 / fMP4 emsg) or, when recording, the file writer's chapter track. A no-op before the
  /// surface is mounted, after the stream stops, or for formats without a metadata channel.
  public func writeTimedMetadata(_ text: String) {
    timedMetadataConsumer?.writeTimedMetadata(text, logger: logger)
  }

  // MARK: - Overlay

  /// Update the overlay buffer and push a frame to encode the change.
  /// Pass nil to clear the overlay.
  ///
  /// In lazy/VFR mode: signals the push loop so the change is encoded promptly. Swapping the buffer
  /// in or out forces a keyframe so consumers that need one to start rendering (e.g. ffplay) see the
  /// change whole; an in-place content update pushes a plain frame — those arrive at the overlay
  /// effect timer's animation cadence (~30fps), and forcing an IDR for each turns the entire stream
  /// into keyframes, starving the motion budget.
  /// In eager/CFR mode: no extra push — the next cadence tick picks up the change without disrupting frame timing.
  public func updateOverlayBuffer(_ overlayBuffer: CVPixelBuffer?) {
    let sameReference = (overlayBuffer === compositor.overlayBuffer)
    if !sameReference {
      compositor.overlayBuffer = overlayBuffer
    }

    let stateDescription = overlayBuffer != nil ? (sameReference ? "contents updated" : "buffer swapped") : "cleared"
    logger.log("Overlay \(stateDescription) (frame=\(frameNumber))")

    switch cadence {
    case .lazy:
      if sameReference {
        lazyTriggers?.signalFrameRendered()
      } else {
        lazyTriggers?.signalKeyFrame()
      }
    case .eager:
      break
    }
  }

  /// Request that the next encoded frame be a keyframe (IDR).
  /// Schedules an extra push on the actor with the VideoToolbox
  /// `kVTEncodeFrameOptionKey_ForceKeyFrame` flag set, so a downstream consumer
  /// that has lost frames (e.g. a WebRTC viewer that has sent a PLI/FIR) can
  /// resync immediately instead of waiting for the next periodic IDR.
  ///
  /// `nonisolated` fire-and-forget: safe to call from any thread. A burst of calls produces a burst
  /// of keyframes — callers are expected to throttle if needed.
  public nonisolated func requestKeyFrame() {
    Task { [weak self] in
      await self?.pushFrame(forceKeyFrame: true)
    }
  }

  // MARK: - Screenshot

  /// Capture a PNG screenshot of the current frame with overlay composited.
  public func captureCompositedScreenshot() throws -> Data {
    guard let sourceBuffer = pixelBuffer else {
      throw SimulatorVideoStreamError.noPixelBufferForScreenshot
    }
    return try compositor.screenshotPNG(of: sourceBuffer)
  }

  // MARK: - Stats

  /// Returns a snapshot of the current video encoder stats.
  /// Returns a zeroed struct if the stream uses a non-encoded format (e.g. bitmap/BGRA).
  public func currentEncoderStats() -> VideoEncoderStats {
    if let pusher = framePusher, let stats = pusher.currentStats() {
      return stats
    }
    return VideoEncoderStats()
  }

  /// Returns a snapshot of the current framebuffer stats (from the underlying Framebuffer).
  /// `nonisolated`: reads only the immutable `framebuffer` reference, whose stats are lock-guarded.
  public nonisolated func currentFramebufferStats() -> FramebufferStats {
    framebuffer.currentStats()
  }

  /// Total number of frames pushed to the encoder since streaming started.
  var currentFrameNumber: UInt { frameNumber }

  /// Wall-clock time when the first frame was pushed, or 0 if not yet started.
  var currentTimeAtFirstFrame: CFTimeInterval { timeAtFirstFrame }

  /// Wall-clock time when the first framebuffer callback was received, or 0 if not yet started.
  /// `nonisolated`: reads only the immutable `framebuffer` reference.
  public nonisolated var framebufferStatsStartTime: CFTimeInterval { framebuffer.statsStartTime }

  // MARK: - VideoStreamOperation

  public func awaitCompletion() async {
    let id = UUID()
    await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        if case .stopped = lifecycle {
          continuation.resume()
          return
        }
        stopAwaiters[id] = continuation
      }
    } onCancel: {
      // Cancelling a completion await stops the stream (mirrors a cancellable completion signal).
      Task { [weak self] in await self?.completionAwaitCancelled(id) }
    }
  }

  /// Stop on behalf of a cancelled completion await, then resume that await regardless of whether
  /// the stop could proceed — a never-started stream has nothing to stop, but the cancelled awaiter
  /// must still return. A successful stop resumes every awaiter, so the removal here finds nothing.
  private func completionAwaitCancelled(_ id: UUID) async {
    try? await stopStreaming()
    if let continuation = stopAwaiters.removeValue(forKey: id) {
      continuation.resume()
    }
  }

  // MARK: - Cadence Loop

  /// The frame push loop shared by both cadences: for each trigger, push a frame and record it.
  ///
  /// Runs on the actor, so each push (and the state it mutates) is serialized with every other isolated
  /// method; the `for await` suspension between triggers lets events, accessors and stop interleave.
  /// Ends on task cancellation or when the stimulus finishes.
  // Concrete overloads rather than one generic loop: iterating a generic `AsyncSequence` from
  // actor-isolated code cannot prove the conformance nonisolated (SE-0470). Static and weakly-held so the
  // loop does not recreate the task↔stream retain cycle.
  private static func runFramePushLoop(stimulus: LazyFrameTriggers, stats: CadenceStats?, stream: () -> SimulatorVideoStream?) async {
    var stats = stats
    for await trigger in stimulus {
      guard !Task.isCancelled else { break }
      guard let stream = stream() else { break }
      let pushDurationMach = await stream.pushTriggered(forceKeyFrame: trigger.forceKeyFrame)
      stats?.record(pushDurationMach: pushDurationMach, overran: trigger.overran)
    }
  }

  private static func runFramePushLoop(stimulus: FrameCadence, stats: CadenceStats?, stream: () -> SimulatorVideoStream?) async {
    var stats = stats
    for await trigger in stimulus {
      guard !Task.isCancelled else { break }
      guard let stream = stream() else { break }
      let pushDurationMach = await stream.pushTriggered(forceKeyFrame: trigger.forceKeyFrame)
      stats?.record(pushDurationMach: pushDurationMach, overran: trigger.overran)
    }
  }

  /// One trigger's worth of work, shared by both cadence loops: push a frame, returning the push
  /// duration in Mach ticks for the caller's cadence statistics.
  private func pushTriggered(forceKeyFrame: Bool) -> UInt64 {
    let beforePush = mach_absolute_time()
    pushFrame(forceKeyFrame: forceKeyFrame)
    return mach_absolute_time() - beforePush
  }
}
