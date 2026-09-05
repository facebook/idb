/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreImage
import CoreMedia
import CoreServices
import CoreVideo
import FBControlCore
import Foundation
import IOSurface
import ImageIO
import Metal
import UniformTypeIdentifiers
import VideoToolbox

enum FBSimulatorVideoStreamError: Error {
  case failedToCreatePixelTransferSession(status: OSStatus)
  case failedToStartCompressionSession(status: OSStatus)
  case compressionSessionNil
  case failedToSetCompressionSessionProperties(status: OSStatus)
  case failedToPrepareCompressionSession(status: OSStatus)
  case missingCompressionSession
  case failedToCompress(status: OSStatus)
  case startWhenStopped
  case startAlreadyStarted
  case stopWithoutConsumer
  case failedToTearDownFramePusher(errorDescription: String)
  case failedToCreatePixelBufferFromSurface(status: CVReturn)
  case failedToCreatePixelBufferFromSurfaceNil
  case mountSurfaceWithoutConsumer
  case noPixelBufferForScreenshot
  case failedToCreateCGImage
  case failedToEncodePNG
}

extension FBSimulatorVideoStreamError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .failedToCreatePixelTransferSession(let status):
      return "Failed to create VTPixelTransferSession: \(status)"
    case .failedToStartCompressionSession(let status):
      return "Failed to start Compression Session \(status)"
    case .compressionSessionNil:
      return "Failed to start Compression Session (nil)"
    case .failedToSetCompressionSessionProperties(let status):
      return "Failed to set compression session properties \(status)"
    case .failedToPrepareCompressionSession(let status):
      return "Failed to prepare compression session \(status)"
    case .missingCompressionSession:
      return "No compression session"
    case .failedToCompress(let status):
      return "Failed to compress \(status)"
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
    case .failedToCreateCGImage:
      return "Failed to create CGImage from pixel buffer"
    case .failedToEncodePNG:
      return "Failed to encode PNG"
    }
  }
}

// MARK: - Value Types

/// Edge insets that extend the output frame dimensions beyond the source framebuffer.
/// Each edge adds opaque pixels for overlay content (label bars, diagnostic stats, etc.).
public struct FBVideoStreamEdgeInsets: Sendable {
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
enum FBVideoStreamCadence {
  case lazy
  case eager(framesPerSecond: UInt)
}

private extension FBVideoStreamCodec {
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

// MARK: - FBSimulatorVideoStream

/// A real-time video stream of a Simulator's framebuffer, written to an `FBDataConsumer`.
///
/// Concurrency model: the actor serializes start/stop, framebuffer event handling, and every frame
/// push. Framebuffer events arrive on the attachment's ordered `AsyncStream`, consumed by an
/// actor-isolated task, rather than queue-delivered callbacks. The cadence is selected by the
/// `cadence` strategy: `.lazy` pushes a frame when a frame-rendered event pokes the trigger stream
/// (variable frame rate), while `.eager` runs a cadence `Task` on the actor that pushes at a fixed frame rate.
public actor FBSimulatorVideoStream: FBVideoStream {

  // MARK: - Properties

  let framebuffer: FBFramebuffer
  let configuration: FBVideoStreamConfiguration
  let edgeInsets: FBVideoStreamEdgeInsets
  let cadence: FBVideoStreamCadence
  /// When set (recording), encoded `.compressed` frames are routed to this sink — an `FBSimulatorVideoFileWriter`
  /// — instead of being byte-framed to `consumer`. nil for streaming.
  let encodedSampleConsumerOverride: FBEncodedSampleConsumer?
  let logger: any FBControlCoreLogger

  // MARK: - Lifecycle

  /// What a started stream holds: the consumer, the framebuffer attachment (whose `cancel()`
  /// detaches this stream), and the task consuming the attachment's ordered event stream onto the
  /// actor (surface changes mount, frame-rendered events poke the `.lazy` trigger; it ends when the
  /// attachment cancels, finishing the stream).
  /// Sendable so the nonisolated `deinit` backstop can reach the attachment and event task.
  private struct Session: Sendable {
    // SAFETY: FBDataConsumer is a thread-safe ObjC protocol that predates Sendable auditing — the
    // `startStreaming` shim already carries it across the boundary on the same justification.
    // patternlint-disable-next-line swift-nonisolated-unsafe
    nonisolated(unsafe) let consumer: any FBDataConsumer
    let attachment: FBFramebufferAttachment
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
  var consumer: (any FBDataConsumer)? {
    switch lifecycle {
    case .idle, .stopped:
      return nil
    case .starting(let session, _), .streaming(let session):
      return session.consumer
    }
  }
  var framePusher: (any FBSimulatorVideoStreamFramePusher)?
  /// The timed-metadata (chapter) sink: the streaming transport writer, or (recording) the file
  /// writer's chapter track. Resolved in `mountSurface`, cleared in `stopStreaming`.
  var timedMetadataConsumer: (any FBTimedMetadataConsumer)?

  // Overlay compositing
  var overlayBuffer: CVPixelBuffer?
  var compositorCIContext: CIContext?
  var compositedBufferPool: CVPixelBufferPool?
  var compositedWidth: Int = 0
  var compositedHeight: Int = 0

  // MARK: - Initializers

  /// Makes a stream with no edge insets. Cadence is derived from `configuration.framesPerSecond`.
  public static func make(framebuffer: FBFramebuffer, configuration: FBVideoStreamConfiguration, logger: any FBControlCoreLogger) -> FBSimulatorVideoStream {
    make(framebuffer: framebuffer, configuration: configuration, edgeInsets: FBVideoStreamEdgeInsets(top: 0, bottom: 0, left: 0, right: 0), logger: logger)
  }

  /// Makes a stream whose output frame is extended by `edgeInsets` (reserved for overlay content).
  public static func make(framebuffer: FBFramebuffer, configuration: FBVideoStreamConfiguration, edgeInsets: FBVideoStreamEdgeInsets, logger: any FBControlCoreLogger) -> FBSimulatorVideoStream {
    FBSimulatorVideoStream(
      framebuffer: framebuffer,
      configuration: configuration,
      edgeInsets: edgeInsets,
      cadence: cadence(for: configuration),
      logger: logger)
  }

  /// Constructs a recording stream: encoded `.compressed` frames are muxed into a file via `fileWriter`
  /// rather than byte-framed to an `FBDataConsumer`. `edgeInsets` (default zero) reserves overlay bar
  /// regions exactly as on the streaming path; set `configuration.framesPerSecond` so the cadence is
  /// eager (a recorded file wants a continuous timeline even while the screen is idle).
  static func makeRecorder(framebuffer: FBFramebuffer, configuration: FBVideoStreamConfiguration, edgeInsets: FBVideoStreamEdgeInsets = FBVideoStreamEdgeInsets(top: 0, bottom: 0, left: 0, right: 0), fileWriter: FBSimulatorVideoFileWriter, logger: any FBControlCoreLogger) -> FBSimulatorVideoStream {
    return FBSimulatorVideoStream(
      framebuffer: framebuffer,
      configuration: configuration,
      edgeInsets: edgeInsets,
      cadence: cadence(for: configuration),
      logger: logger,
      encodedSampleConsumerOverride: fileWriter)
  }

  /// Makes and starts a stream to `consumer`.
  public static func start(framebuffer: FBFramebuffer, configuration: FBVideoStreamConfiguration, edgeInsets: FBVideoStreamEdgeInsets = FBVideoStreamEdgeInsets(top: 0, bottom: 0, left: 0, right: 0), to consumer: any FBDataConsumer, logger: any FBControlCoreLogger) async throws -> FBSimulatorVideoStream {
    let stream = make(framebuffer: framebuffer, configuration: configuration, edgeInsets: edgeInsets, logger: logger)
    try await stream.startStreaming(consumer)
    return stream
  }

  /// Eager (constant-frame-rate) when a positive `framesPerSecond` is set, else lazy (variable-rate,
  /// driven by damage events).
  private static func cadence(for configuration: FBVideoStreamConfiguration) -> FBVideoStreamCadence {
    guard let framesPerSecond = configuration.framesPerSecond, framesPerSecond > 0 else {
      return .lazy
    }
    return .eager(framesPerSecond: UInt(framesPerSecond))
  }

  init(framebuffer: FBFramebuffer, configuration: FBVideoStreamConfiguration, edgeInsets: FBVideoStreamEdgeInsets, cadence: FBVideoStreamCadence, logger: any FBControlCoreLogger, encodedSampleConsumerOverride: FBEncodedSampleConsumer? = nil) {
    self.framebuffer = framebuffer
    self.configuration = configuration
    self.edgeInsets = edgeInsets
    self.cadence = cadence
    self.encodedSampleConsumerOverride = encodedSampleConsumerOverride
    self.logger = logger
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

  public nonisolated func startStreaming(_ consumer: any FBDataConsumer) async throws {
    // FBDataConsumer is a thread-safe ObjC protocol that isn't Sendable; this single shim carries it
    // onto the actor, where it is confined thereafter.
    // patternlint-disable-next-line swift-nonisolated-unsafe
    nonisolated(unsafe) let consumer = consumer
    try await isolatedStartStreaming(consumer)
  }

  private func isolatedStartStreaming(_ consumer: any FBDataConsumer) async throws {
    switch lifecycle {
    case .starting, .streaming:
      throw FBSimulatorVideoStreamError.startAlreadyStarted
    case .stopped:
      throw FBSimulatorVideoStreamError.startWhenStopped
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
      throw FBSimulatorVideoStreamError.stopWithoutConsumer
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
    overlayBuffer = nil
    compositedBufferPool = nil
    cadenceTeardown()
    resumeStopAwaiters()
    for awaiter in pendingStartAwaiters {
      awaiter.resume(throwing: FBSimulatorVideoStreamError.startWhenStopped)
    }
    if let tearDownError {
      throw FBSimulatorVideoStreamError.failedToTearDownFramePusher(errorDescription: "\(tearDownError)")
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

  // MARK: - Private

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
  /// unbounded event stream's drain invariant: a surface change mounts once; a rendered frame pokes
  /// the `.lazy` trigger, whose `bufferingNewest(1)` coalescing keeps real-time frame dropping where
  /// it belongs. In `.eager` mode the cadence clock drives pushes, so frame-rendered events are ignored.
  private func handle(_ event: FBFramebufferEvent) {
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
      throw FBSimulatorVideoStreamError.failedToCreatePixelBufferFromSurface(status: status)
    }
    guard let buffer = unmanagedBuffer?.takeRetainedValue() else {
      throw FBSimulatorVideoStreamError.failedToCreatePixelBufferFromSurfaceNil
    }

    guard let consumer else {
      throw FBSimulatorVideoStreamError.mountSurfaceWithoutConsumer
    }

    let attributes = bitmapStreamPixelBufferAttributes(from: buffer)
    logger.log("Mounting Surface with Attributes: \(FBCollectionInformation.oneLineDescription(from: attributes))")

    let framePusher = try Self.framePusher(
      configuration: configuration,
      compressionSessionProperties: compressionSessionProperties,
      consumer: consumer,
      encodedSampleConsumerOverride: encodedSampleConsumerOverride,
      logger: logger)
    try framePusher.setup(with: buffer, edgeInsets: edgeInsets)

    // Published only once every throwing step is past, so a mount is all-or-nothing: a failed one
    // leaves the previous surface installed rather than a new `pixelBuffer` behind a pusher never
    // set up for it.
    self.pixelBuffer = buffer
    self.pixelBufferAttributes = attributes
    self.framePusher = framePusher
    let transportTimedMetadataWriter =
      (framePusher as? FBSimulatorVideoStreamFramePusher_VideoToolbox)?.timedMetadataWriter

    // Resolve the timed-metadata (chapter) sink. A recording file writer that supports chapters
    // supplies its own consumer; otherwise the streaming transport writer (fMP4 emsg / MPEG-TS ID3)
    // handles markers, dropping them on transports with no metadata channel.
    if case .compressedVideo = configuration.format {
      self.timedMetadataConsumer =
        (encodedSampleConsumerOverride as? FBTimedMetadataConsumer)
        ?? FBTransportTimedMetadataConsumer(consumer: consumer, timedMetadataWriter: transportTimedMetadataWriter)
    }

    if compositorCIContext == nil {
      if let device = MTLCreateSystemDefaultDevice() {
        compositorCIContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
      } else {
        compositorCIContext = CIContext(options: [.cacheIntermediates: false])
      }
    }
    compositedBufferPool = nil
    let insets = edgeInsets
    // Must agree exactly with the encoder's dimensions — both derive from FBVideoOutputDimensions.
    let dimensions = FBVideoOutputDimensions.calculate(
      sourceWidth: CVPixelBufferGetWidth(buffer), sourceHeight: CVPixelBufferGetHeight(buffer),
      scaleFactor: configuration.scaleFactor, edgeInsets: insets)
    let compositedWidth = dimensions.width
    let compositedHeight = dimensions.height
    self.compositedWidth = compositedWidth
    self.compositedHeight = compositedHeight
    let compositedPoolAttrs: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: compositedWidth,
      kCVPixelBufferHeightKey as String: compositedHeight,
      kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
    ]
    var pool: CVPixelBufferPool?
    CVPixelBufferPoolCreate(nil, nil, compositedPoolAttrs as CFDictionary, &pool)
    compositedBufferPool = pool
    if insets.top + insets.bottom + insets.left + insets.right > 0 {
      logger.info().log("Composited pool includes edge insets (t=\(insets.top) b=\(insets.bottom) l=\(insets.left) r=\(insets.right)): w=\(compositedWidth)/h=\(compositedHeight)")
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
        await Self.runFramePushLoop(stimulus: FrameCadence(framesPerSecond: framesPerSecond, logger: logger), stats: stats) { self }
      }
    case .lazy:
      let triggers = LazyFrameTriggers()
      lazyTriggers = triggers
      framePusherTask = Task { [weak self] in
        await Self.runFramePushLoop(stimulus: triggers, stats: nil) { self }
      }
    }
  }

  /// Build a composited CIImage from the source pixel buffer, applying edge insets
  /// and overlaying the overlay buffer if present. Returns nil if no compositing is needed.
  func compositedImage(fromSource sourceBuffer: CVPixelBuffer) -> CIImage? {
    let overlayBuf = overlayBuffer
    let insets = edgeInsets
    let hasInsets = (insets.top + insets.bottom + insets.left + insets.right) > 0
    let needsComposite = hasInsets || (overlayBuf != nil)
    guard needsComposite, compositorCIContext != nil, compositedBufferPool != nil else {
      return nil
    }

    var sourceImage = CIImage(cvPixelBuffer: sourceBuffer)

    // Scale source to fit within the composited output (excluding insets).
    // CIImage origin is bottom-left, so after scaling we translate by (left, bottom)
    // to position the video content inside the inset frame.
    let sourceW = CVPixelBufferGetWidth(sourceBuffer)
    let targetW = compositedWidth - Int(insets.left) - Int(insets.right)
    if targetW != sourceW && sourceW > 0 {
      let s = CGFloat(targetW) / CGFloat(sourceW)
      sourceImage = sourceImage.transformed(by: CGAffineTransform(scaleX: s, y: s))
    }
    if insets.left > 0 || insets.bottom > 0 {
      sourceImage = sourceImage.transformed(by: CGAffineTransform(translationX: CGFloat(insets.left), y: CGFloat(insets.bottom)))
    }

    var result = sourceImage
    if let overlayBuf {
      let overlayImage = CIImage(cvPixelBuffer: overlayBuf)
      result = overlayImage.composited(over: sourceImage)
    }
    return result
  }

  func pushFrame(forceKeyFrame: Bool) {
    guard let pixelBuffer, let consumer, let framePusher else {
      return
    }
    if !checkConsumerBufferLimit(consumer, logger) {
      return
    }

    let now = CFAbsoluteTimeGetCurrent()
    let frameNumber = self.frameNumber
    if frameNumber == 0 {
      timeAtFirstFrame = now
    }
    let timeAtFirstFrame = self.timeAtFirstFrame
    let frameDuration = timeAtLastPush > 0 ? (now - timeAtLastPush) : 0
    timeAtLastPush = now

    // Composite the overlay buffer over the source frame, or apply edge inset padding.
    // When any edge inset > 0, every frame must be composited to match the output dimensions
    // of the encoder (which includes the insets). Without this, raw framebuffer pixels
    // would be fed to an encoder sized for the larger output, causing distortion.
    var bufferToEncode = pixelBuffer
    if let composited = compositedImage(fromSource: pixelBuffer), let compositedBufferPool {
      var compositedBuffer: CVPixelBuffer?
      let poolStatus = CVPixelBufferPoolCreatePixelBuffer(nil, compositedBufferPool, &compositedBuffer)
      if poolStatus == kCVReturnSuccess, let compositedBuffer {
        compositorCIContext?.render(composited, to: compositedBuffer)
        bufferToEncode = compositedBuffer
      }
    }

    try? framePusher.writeEncodedFrame(
      bufferToEncode,
      frameNumber: frameNumber,
      timeAtFirstFrame: timeAtFirstFrame,
      frameDuration: frameDuration,
      forceKeyFrame: forceKeyFrame)

    self.frameNumber = frameNumber + 1
  }

  // MARK: - Compression Properties

  /// The `VTSessionSetProperties` dictionary for `configuration`, with `callerProperties` layered on top.
  public static func compressionSessionProperties(for configuration: FBVideoStreamConfiguration, callerProperties: [String: Any]) -> [String: Any] {
    var derived: [String: Any] = [
      kVTCompressionPropertyKey_RealTime as String: true,
      kVTCompressionPropertyKey_AllowFrameReordering as String: false,
      kVTCompressionPropertyKey_MaxFrameDelayCount as String: 0,
    ]

    switch configuration.rateControl {
    case .automatic:
      // JPEG formats honor the quality knob (the value the pre-automatic default used). For
      // H.264/HEVC no rate key is set here: the VideoToolbox pusher derives an average bitrate at
      // session setup, where the encoded output dimensions are known.
      switch configuration.format {
      case .mjpeg, .minicap:
        derived[kVTCompressionPropertyKey_Quality as String] = 0.75
      case .compressedVideo, .bgra:
        break
      }
    case let .bitrate(bitrate):
      // Explicit bitrate: AverageBitRate is in bits/sec
      derived[kVTCompressionPropertyKey_AverageBitRate as String] = bitrate
    case let .quality(quality):
      derived[kVTCompressionPropertyKey_Quality as String] = quality
    }

    for (key, value) in callerProperties {
      derived[key] = value
    }
    derived[kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration as String] = configuration.keyFrameRate
    if case let .compressedVideo(codec, _) = configuration.format {
      switch codec {
      case .h264:
        derived[kVTCompressionPropertyKey_ProfileLevel as String] = kVTProfileLevel_H264_High_AutoLevel as String
        derived[kVTCompressionPropertyKey_H264EntropyMode as String] = kVTH264EntropyMode_CABAC as String
      case .hevc:
        derived[kVTCompressionPropertyKey_AllowOpenGOP as String] = false
        derived[kVTCompressionPropertyKey_ProfileLevel as String] = kVTProfileLevel_HEVC_Main10_AutoLevel as String
      }
    }
    return derived
  }

  static func framePusher(
    configuration: FBVideoStreamConfiguration,
    compressionSessionProperties: [String: Any],
    consumer: any FBDataConsumer,
    encodedSampleConsumerOverride: FBEncodedSampleConsumer?,
    logger: any FBControlCoreLogger
  ) throws -> any FBSimulatorVideoStreamFramePusher {
    let derived = Self.compressionSessionProperties(for: configuration, callerProperties: compressionSessionProperties)
    switch configuration.format {
    case let .compressedVideo(codec, transport):
      let frameWriters = transport.frameWriters(for: codec)
      let encodedSampleConsumer: FBEncodedSampleConsumer =
        encodedSampleConsumerOverride
        ?? FBDataConsumerEncodedSampleConsumer(consumer: consumer, frameWriter: frameWriters.frameWriter, timedMetadataWriter: frameWriters.timedMetadataWriter)
      return FBSimulatorVideoStreamFramePusher_VideoToolbox(
        configuration: configuration, compressionSessionProperties: derived, videoCodec: codec.videoToolboxCodec,
        consumer: consumer, outputMode: .compressed, encodedSampleConsumer: encodedSampleConsumer, timedMetadataWriter: frameWriters.timedMetadataWriter, logger: logger)
    case .mjpeg:
      return FBSimulatorVideoStreamFramePusher_VideoToolbox(
        configuration: configuration, compressionSessionProperties: derived, videoCodec: kCMVideoCodecType_JPEG,
        consumer: consumer, outputMode: .mjpeg, encodedSampleConsumer: nil, timedMetadataWriter: nil, logger: logger)
    case .minicap:
      return FBSimulatorVideoStreamFramePusher_VideoToolbox(
        configuration: configuration, compressionSessionProperties: derived, videoCodec: kCMVideoCodecType_JPEG,
        consumer: consumer, outputMode: .minicap, encodedSampleConsumer: nil, timedMetadataWriter: nil, logger: logger)
    case .bgra:
      return FBSimulatorVideoStreamFramePusher_Bitmap(consumer: consumer, scaleFactor: configuration.scaleFactor)
    }
  }

  /// Caller-provided compression session properties. In `.eager` mode these add the fixed frame rate
  /// (`ExpectedFrameRate`) and a long keyframe interval (`MaxKeyFrameInterval`) suited to a constant
  /// cadence; in `.lazy` mode there are none (the base, variable-frame-rate value).
  var compressionSessionProperties: [String: Any] {
    switch cadence {
    case .lazy:
      return [:]
    case let .eager(framesPerSecond):
      return [
        kVTCompressionPropertyKey_ExpectedFrameRate as String: framesPerSecond,
        kVTCompressionPropertyKey_MaxKeyFrameInterval as String: 360,
      ]
    }
  }

  // MARK: - Timed Metadata

  /// Write a timed metadata marker (chapter) at the current stream position. Routed to the
  /// `FBTimedMetadataConsumer` resolved in `mountSurface` — the streaming transport writer
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
    let sameReference = (overlayBuffer === self.overlayBuffer)

    // Skip atomic self-assignment when the caller is updating buffer contents in-place.
    if !sameReference {
      self.overlayBuffer = overlayBuffer
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

  // MARK: - Keyframe Requests

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
      throw FBSimulatorVideoStreamError.noPixelBufferForScreenshot
    }

    // Only a CGImage is needed here, so render the composited CIImage directly rather than via a pool buffer.
    let ciImage = compositedImage(fromSource: sourceBuffer) ?? CIImage(cvPixelBuffer: sourceBuffer)

    let ctx = compositorCIContext ?? CIContext()
    guard let cgImage = ctx.createCGImage(ciImage, from: ciImage.extent) else {
      throw FBSimulatorVideoStreamError.failedToCreateCGImage
    }

    let pngData = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(pngData as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
      throw FBSimulatorVideoStreamError.failedToEncodePNG
    }
    CGImageDestinationAddImage(dest, cgImage, nil)
    let finalized = CGImageDestinationFinalize(dest)

    if !finalized {
      throw FBSimulatorVideoStreamError.failedToEncodePNG
    }

    return pngData as Data
  }

  // MARK: - Stats

  /// Returns a snapshot of the current video encoder stats.
  /// Returns a zeroed struct if the stream uses a non-encoded format (e.g. bitmap/BGRA).
  public func currentEncoderStats() -> FBVideoEncoderStats {
    if let pusher = framePusher, let stats = pusher.currentStats() {
      return stats
    }
    return FBVideoEncoderStats()
  }

  /// Returns a snapshot of the current framebuffer stats (from the underlying FBFramebuffer).
  /// `nonisolated`: reads only the immutable `framebuffer` reference, whose stats are lock-guarded.
  public nonisolated func currentFramebufferStats() -> FBFramebufferStats {
    framebuffer.currentStats()
  }

  /// Total number of frames pushed to the encoder since streaming started.
  var currentFrameNumber: UInt { frameNumber }

  /// Wall-clock time when the first frame was pushed, or 0 if not yet started.
  var currentTimeAtFirstFrame: CFTimeInterval { timeAtFirstFrame }

  /// Wall-clock time when the first framebuffer callback was received, or 0 if not yet started.
  /// `nonisolated`: reads only the immutable `framebuffer` reference.
  public nonisolated var framebufferStatsStartTime: CFTimeInterval { framebuffer.statsStartTime }

  // MARK: - FBVideoStream

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
  private static func runFramePushLoop(stimulus: LazyFrameTriggers, stats: CadenceStats?, stream: () -> FBSimulatorVideoStream?) async {
    var stats = stats
    for await trigger in stimulus {
      guard !Task.isCancelled else { break }
      guard let stream = stream() else { break }
      let pushDurationMach = await stream.pushTriggered(forceKeyFrame: trigger.forceKeyFrame)
      stats?.record(pushDurationMach: pushDurationMach, overran: trigger.overran)
    }
  }

  private static func runFramePushLoop(stimulus: FrameCadence, stats: CadenceStats?, stream: () -> FBSimulatorVideoStream?) async {
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
