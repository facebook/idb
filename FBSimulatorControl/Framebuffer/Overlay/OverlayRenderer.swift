/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import CoreText
import CoreVideo
import FBControlCore
import Foundation
import QuartzCore

/// The content mode for a status bar slot.
public enum FBBarContent: Equatable {
  /// Display the given text in the bar.
  case text(String)
  /// Display live stats from the internal 1Hz writer.
  case stats
  /// Bar is hidden — no background, no text.
  case hidden
}

/// Layout mode for a status bar — determines how the bar interacts with the simulator screen.
public enum FBBarMode: String {
  /// Bar lives in canvas space reserved via edgeInsets. Nothing renders behind it, so the
  /// background is fully opaque. The simulator screen is pushed away from the reserved edge.
  case pad
  /// Bar is drawn on top of the simulator screen at the requested edge. The canvas size matches
  /// the simulator screen; the bar covers screen pixels with a semi-transparent background so
  /// the underlying content peeks through.
  case overlay
}

/// Renders overlay shapes into a CVPixelBuffer for compositing over video frames.
///
/// The renderer owns a single IOSurface-backed BGRA+alpha CVPixelBuffer that is
/// reused across renders. Call `render(overlays:)` to draw shapes, then pass `buffer`
/// to `FBSimulatorVideoStream.updateOverlayBuffer()` to trigger a frame push.
///
/// For animated effects (fadeout, fadein, translate), call `startEffectTimer(onTick:)`
/// after rendering. The timer re-renders at ~30fps until all effects complete.
public final class FBOverlayRenderer {
  public let buffer: CVPixelBuffer
  let width: Int
  let height: Int
  public let transform: FBOverlayCoordinateTransform

  /// Injectable time source for monotonic time (seconds). Defaults to `CACurrentMediaTime()`.
  /// Override in tests to control animation progress deterministically.
  var currentTime: () -> CFTimeInterval = { CACurrentMediaTime() }

  /// A shape with its start time, classified as persistent or animating.
  ///
  /// - `persistent`: No effect — replaced wholesale on each `render(overlays:)` call.
  /// - `animating`: Has an active effect (fadeout, fadein, translate) — survives across
  ///   subsequent `render(overlays:)` calls until the effect expires.
  private enum TimedShape {
    case persistent(FBOverlayShape, startTime: CFTimeInterval)
    case animating(FBOverlayShape, startTime: CFTimeInterval)

    var shape: FBOverlayShape {
      switch self {
      case .persistent(let s, _), .animating(let s, _): return s
      }
    }

    var startTime: CFTimeInterval {
      switch self {
      case .persistent(_, let t), .animating(_, let t): return t
      }
    }

    var isAnimating: Bool {
      switch self {
      case .animating: return true
      case .persistent: return false
      }
    }
  }

  private var shapes: [TimedShape] = []
  private var effectTimer: DispatchSourceTimer?
  private let effectQueue = DispatchQueue(label: "com.facebook.sime2e.overlay-effects")

  /// Serializes access to the renderer's mutable state (`shapes`, the bar dictionaries, `statsText`,
  /// `effectTimer`) and the buffer render. The renderer is driven from several threads — the
  /// `@MainActor` stdin handler, the background 1Hz stats writer, and the effect timer's own queue —
  /// so without this every mutation would race (a concurrent `statsText` write/read corrupts the
  /// dictionary and crashes). Recursive so a locked method can call `renderToBuffer()` while held.
  private let stateLock = NSRecursiveLock()

  /// Logger for diagnostic output. Set after init from the simulator's logger.
  public var logger: FBControlCoreLogger?

  /// Current content mode for each bar position.
  public private(set) var barContent: [String: FBBarContent] = [:]

  /// Live stats text written by the internal 1Hz timer. Only displayed when the bar's content
  /// mode is `.stats`. The renderer never reads this unless the bar is in stats mode.
  private(set) var statsText: [String: String] = [:]

  /// Layout mode for each bar position. Defaults to `.pad` for any position not explicitly set.
  /// `pad` mode draws an opaque background; `overlay` mode draws a partially-transparent
  /// background so the simulator content beneath shows through.
  public private(set) var barMode: [String: FBBarMode] = [:]

  /// Per-position shrink-to-fit flag. When true, the bar's font size is reduced so the rendered
  /// text width fits within the bar (minus padding). Applies to whatever the bar currently
  /// displays — fixed text and stats text alike. Defaults to false (no shrinking; long text
  /// renders past the bar's right edge and is visually clipped).
  public private(set) var barFit: [String: Bool] = [:]

  /// Convenience init for testing — creates a transform from width/height/scale.
  public convenience init(width: Int, height: Int, scaleFactor: CGFloat = 1.0) {
    let transform = FBOverlayCoordinateTransform(
      screenPixelWidth: width,
      screenPixelHeight: height,
      retinaScale: 1.0,
      videoScale: scaleFactor,
      borderTop: 0,
      scaledBorderTop: 0,
      borderBottom: 0,
      scaledBorderBottom: 0
    )
    self.init(transform: transform)
  }

  public init(transform: FBOverlayCoordinateTransform) {
    let width = transform.bufferWidth
    let height = transform.bufferHeight
    var pixelBuffer: CVPixelBuffer?
    let attrs: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: width,
      kCVPixelBufferHeightKey as String: height,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
    ]
    CVPixelBufferCreate(
      nil, width, height, kCVPixelFormatType_32BGRA,
      attrs as CFDictionary, &pixelBuffer)
    guard let createdBuffer = pixelBuffer else {
      fatalError("CVPixelBufferCreate failed for \(width)x\(height) BGRA buffer")
    }
    self.buffer = createdBuffer
    self.width = width
    self.height = height
    self.transform = transform

    // Initialize to fully transparent.
    clearBuffer()
  }

  /// The overlay scale factor from the transform, for backward compatibility.
  var scaleFactor: CGFloat { transform.overlayScale }

  /// Render the given overlays into the buffer.
  ///
  /// Shapes with effects become `.animating` and persist across subsequent renders
  /// until their effect completes. Shapes without effects become `.persistent` and
  /// replace the previous persistent set on each call.
  public func render(overlays: [FBOverlayShape]) {
    stateLock.lock()
    defer { stateLock.unlock() }
    let now = currentTime()

    // Keep in-flight animating shapes, drop expired ones.
    var kept = shapes.filter { timedShape in
      guard timedShape.isAnimating else { return false }
      let elapsed = now - timedShape.startTime
      return isEffectActive(effectForShape(timedShape.shape), elapsed: elapsed)
    }

    // Classify incoming shapes.
    for shape in overlays {
      if effectForShape(shape) != nil {
        kept.append(.animating(shape, startTime: now))
      } else {
        kept.append(.persistent(shape, startTime: now))
      }
    }

    self.shapes = kept
    renderToBuffer()
  }

  /// Clear the overlay buffer to fully transparent.
  public func clear() {
    stateLock.lock()
    defer { stateLock.unlock() }
    stopEffectTimer()
    shapes = []
    clearBuffer()
  }

  /// Returns true if any shape has an active (non-completed) effect.
  func hasActiveEffects() -> Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    let now = currentTime()
    return shapes.contains { timedShape in
      let elapsed = now - timedShape.startTime
      return isEffectActive(effectForShape(timedShape.shape), elapsed: elapsed)
    }
  }

  /// Start a timer that re-renders the overlay at ~30fps for effect animations.
  ///
  /// If a timer is already running, this is a no-op — the existing timer will
  /// continue rendering and self-cancel when all effects expire.
  public func startEffectTimer(onTick: @escaping () -> Void) {
    stateLock.lock()
    defer { stateLock.unlock() }
    if effectTimer != nil { return }
    guard hasActiveEffects() else { return }

    let timer = DispatchSource.makeTimerSource(queue: effectQueue)
    timer.schedule(deadline: .now(), repeating: .milliseconds(33))
    timer.setEventHandler { [weak self] in
      guard let self else {
        timer.cancel()
        return
      }
      self.renderToBuffer()
      onTick()
      if !self.hasActiveEffects() {
        self.stopEffectTimer()
      }
    }
    effectTimer = timer
    timer.resume()
  }

  /// Set the content mode for a bar at the given position. Re-renders the buffer.
  public func setBarContent(_ content: FBBarContent, position: String) {
    stateLock.lock()
    defer { stateLock.unlock() }
    barContent[position] = content
    renderToBuffer()
  }

  /// Update the live stats text for a position (called by the 1Hz timer).
  /// Only triggers a re-render if the bar is currently in `.stats` mode.
  public func setStatsText(_ text: String, position: String) {
    stateLock.lock()
    defer { stateLock.unlock() }
    statsText[position] = text
    if barContent[position] == .stats {
      renderToBuffer()
    }
  }

  /// Set the layout mode for a bar position.
  public func setBarMode(_ mode: FBBarMode, position: String) {
    stateLock.lock()
    defer { stateLock.unlock() }
    barMode[position] = mode
  }

  /// Set the shrink-to-fit flag for a bar position.
  public func setBarFit(_ fit: Bool, position: String) {
    stateLock.lock()
    defer { stateLock.unlock() }
    barFit[position] = fit
  }

  func stopEffectTimer() {
    stateLock.lock()
    defer { stateLock.unlock() }
    effectTimer?.cancel()
    effectTimer = nil
  }

  // MARK: - Private

  private func clearBuffer() {
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return }
    let size = CVPixelBufferGetBytesPerRow(buffer) * height
    memset(baseAddress, 0, size)
  }

  /// Re-render all shapes into the pixel buffer at the current time.
  ///
  /// Internal (not private) so tests can trigger re-renders at controlled time points
  /// via the injectable `currentTime` closure.
  public func renderToBuffer() {
    stateLock.lock()
    defer { stateLock.unlock() }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

    let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    guard
      let context = CGContext(
        data: baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo
      )
    else { return }

    context.clear(CGRect(x: 0, y: 0, width: width, height: height))

    // CoreGraphics has origin at bottom-left; flip to top-left to match screen coordinates.
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)

    let now = currentTime()
    for timedShape in shapes {
      let elapsed = now - timedShape.startTime
      renderShape(timedShape.shape, context: context, elapsed: elapsed)
    }

    renderBarIfActive("bottom", context: context)
    renderBarIfActive("top", context: context)
  }

  private func renderShape(_ shape: FBOverlayShape, context: CGContext, elapsed: CFTimeInterval) {
    switch shape {
    case .circle(let c):
      let bp = transform.bufferPoint(x: c.x, y: c.y)
      logger?.log("Overlay circle: input=(\(c.x),\(c.y)) r=\(c.radius) -> buffer=(\(bp.x),\(bp.y)) r=\(transform.bufferSize(width: c.radius, height: 0).width) [scale=\(transform.overlayScale), buffer=\(width)x\(height)]")
      renderCircle(c, context: context, elapsed: elapsed)
    case .rectangle(let r):
      let br = transform.bufferRect(x: r.x, y: r.y, width: r.width, height: r.height)
      logger?.log("Overlay rect: input=(\(r.x),\(r.y),\(r.width),\(r.height)) -> buffer=(\(br.origin.x),\(br.origin.y),\(br.size.width),\(br.size.height)) [scale=\(transform.overlayScale), buffer=\(width)x\(height)]")
      renderRectangle(r, context: context, elapsed: elapsed)
    case .label(let l):
      renderLabel(l, context: context)
    }
  }

  // MARK: - Circle

  private func renderCircle(_ circle: FBOverlayShape.Circle, context: CGContext, elapsed: CFTimeInterval) {
    let alpha = effectAlpha(circle.effect, baseAlpha: circleAlpha(circle.rgba), elapsed: elapsed)
    guard alpha > 0 else { return }

    var center = transform.bufferPoint(x: circle.x, y: circle.y)
    if let effect = circle.effect {
      center = effectPosition(effect, base: center, elapsed: elapsed)
    }

    let color = CGColor(
      red: circleRed(circle.rgba),
      green: circleGreen(circle.rgba),
      blue: circleBlue(circle.rgba),
      alpha: alpha
    )
    context.setFillColor(color)
    let scaledRadius = transform.bufferSize(width: circle.radius, height: 0).width
    let rect = CGRect(
      x: center.x - scaledRadius,
      y: center.y - scaledRadius,
      width: scaledRadius * 2,
      height: scaledRadius * 2
    )
    context.fillEllipse(in: rect)
  }

  // MARK: - Rectangle

  private func renderRectangle(_ rect: FBOverlayShape.Rectangle, context: CGContext, elapsed: CFTimeInterval) {
    let alpha = effectAlpha(rect.effect, baseAlpha: circleAlpha(rect.rgba), elapsed: elapsed)
    guard alpha > 0 else { return }

    let r = transform.bufferRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)

    let color = CGColor(
      red: circleRed(rect.rgba),
      green: circleGreen(rect.rgba),
      blue: circleBlue(rect.rgba),
      alpha: alpha
    )
    context.setFillColor(color)
    context.fill(r)
  }

  // MARK: - Label

  private func renderLabel(_ label: FBOverlayShape.Label, context: CGContext) {
    let (fontName, baseFontSize) = parseFontSpec(label.font)
    let fontSize = transform.labelFontSize(baseFontSize)
    let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
    let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    let attributes: [NSAttributedString.Key: Any] = [
      .init(rawValue: kCTFontAttributeName as String): font,
      .init(rawValue: kCTForegroundColorAttributeName as String): white,
    ]
    let attrString = NSAttributedString(string: label.text, attributes: attributes)
    let line = CTLineCreateWithAttributedString(attrString)

    let ascent = CTFontGetAscent(font)
    let descent = CTFontGetDescent(font)
    let origin = transform.labelOrigin(padding: label.padding, ascent: ascent, descent: descent)
    context.saveGState()
    context.translateBy(x: origin.x, y: origin.y)
    context.scaleBy(x: 1, y: -1)
    context.textPosition = .zero
    CTLineDraw(line, context)
    context.restoreGState()
  }

  // MARK: - Font Parsing

  /// Parse a Pango-style font spec "FontName Size" (e.g. "Monaco 8").
  func parseFontSpec(_ spec: String) -> (String, CGFloat) {
    let trimmed = spec.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return ("Monaco", 8) }
    if let lastSpace = trimmed.lastIndex(of: " ") {
      let name = String(trimmed[trimmed.startIndex..<lastSpace])
      let sizeStr = String(trimmed[trimmed.index(after: lastSpace)...])
      if let size = Double(sizeStr), size > 0 {
        return (name, CGFloat(size))
      }
    }
    return (trimmed, 8)
  }

  // MARK: - Status Bars

  private func renderBarIfActive(_ position: String, context: CGContext) {
    let content = barContent[position] ?? .hidden
    let text: String
    switch content {
    case .text(let t):
      text = t
    case .stats:
      text = statsText[position] ?? ""
    case .hidden:
      return
    }
    let mode = barMode[position] ?? .pad
    let fit = barFit[position] ?? false
    drawStatusBar(
      text: text,
      fontSize: transform.barFontSize(),
      barY: transform.barY(position: position),
      barHeight: transform.barHeight(),
      mode: mode,
      fit: fit,
      context: context
    )
  }

  private func drawStatusBar(
    text: String,
    fontSize: CGFloat,
    barY: CGFloat,
    barHeight: CGFloat,
    mode: FBBarMode,
    fit: Bool,
    context: CGContext
  ) {
    let padding: CGFloat = 4

    // pad mode: bar fills reserved canvas space, opaque so PNG and live video read the same.
    // overlay mode: bar covers simulator screen content, partial alpha lets it peek through.
    let bgAlpha: CGFloat = mode == .overlay ? 0.7 : 1.0
    let bgColor = CGColor(red: 0, green: 0, blue: 0, alpha: bgAlpha)
    context.setFillColor(bgColor)
    context.fill(CGRect(x: 0, y: barY, width: CGFloat(width), height: barHeight))

    // Choose final font size — shrink to fit when requested and the text overflows the bar.
    let availableWidth = CGFloat(width) - padding * 2
    let (font, line) = makeLine(text: text, fontSize: fontSize, availableWidth: availableWidth, fit: fit)

    let ascent = CTFontGetAscent(font)
    let drawY = barY + padding + ascent
    context.saveGState()
    context.translateBy(x: padding, y: drawY)
    context.scaleBy(x: 1, y: -1)
    context.textPosition = .zero
    CTLineDraw(line, context)
    context.restoreGState()
  }

  /// Build the bar's `CTLine` at the requested point size, optionally shrinking to fit.
  /// Returns the final `CTFont` (for ascent measurement) and the laid-out `CTLine`.
  private func makeLine(text: String, fontSize: CGFloat, availableWidth: CGFloat, fit: Bool) -> (CTFont, CTLine) {
    let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    func buildLine(_ size: CGFloat) -> (CTFont, CTLine) {
      let font = CTFontCreateWithName("Monaco" as CFString, size, nil)
      let attributes: [NSAttributedString.Key: Any] = [
        .init(rawValue: kCTFontAttributeName as String): font,
        .init(rawValue: kCTForegroundColorAttributeName as String): white,
      ]
      let attrString = NSAttributedString(string: text, attributes: attributes)
      return (font, CTLineCreateWithAttributedString(attrString))
    }
    let (font, line) = buildLine(fontSize)
    guard fit else {
      return (font, line)
    }
    let textWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    guard textWidth > availableWidth, textWidth > 0 else {
      return (font, line)
    }
    let shrunkSize = fontSize * (availableWidth / textWidth)
    return buildLine(shrunkSize)
  }

  // MARK: - Effect Helpers

  private func effectForShape(_ shape: FBOverlayShape) -> FBOverlayShape.Effect? {
    switch shape {
    case .circle(let c): return c.effect
    case .rectangle(let r): return r.effect
    case .label: return nil
    }
  }

  private func circleRed(_ rgba: [CGFloat]) -> CGFloat { rgba.count > 0 ? rgba[0] / 255.0 : 0 }
  private func circleGreen(_ rgba: [CGFloat]) -> CGFloat { rgba.count > 1 ? rgba[1] / 255.0 : 0 }
  private func circleBlue(_ rgba: [CGFloat]) -> CGFloat { rgba.count > 2 ? rgba[2] / 255.0 : 0 }
  private func circleAlpha(_ rgba: [CGFloat]) -> CGFloat { rgba.count > 3 ? rgba[3] : 1 }

  private func effectAlpha(_ effect: FBOverlayShape.Effect?, baseAlpha: CGFloat, elapsed: CFTimeInterval) -> CGFloat {
    guard let effect else { return baseAlpha }
    switch effect {
    case .fadeout(let fade):
      let progress = min(1.0, elapsed / (Double(fade.durationMs) / 1000.0))
      return baseAlpha * CGFloat(1.0 - progress)
    case .fadein(let fade):
      let progress = min(1.0, elapsed / (Double(fade.durationMs) / 1000.0))
      return baseAlpha * CGFloat(progress)
    case .translate:
      return baseAlpha
    }
  }

  private func effectPosition(_ effect: FBOverlayShape.Effect, base: CGPoint, elapsed: CFTimeInterval) -> CGPoint {
    switch effect {
    case .translate(let t):
      let progress = min(1.0, elapsed / (Double(t.durationMs) / 1000.0))
      let target = transform.translateTarget(x: t.x, y: t.y)
      let x = base.x + (target.x - base.x) * CGFloat(progress)
      let y = base.y + (target.y - base.y) * CGFloat(progress)
      return CGPoint(x: x, y: y)
    default:
      return base
    }
  }

  private func isEffectActive(_ effect: FBOverlayShape.Effect?, elapsed: CFTimeInterval) -> Bool {
    guard let effect else { return false }
    switch effect {
    case .fadeout(let fade): return elapsed < Double(fade.durationMs) / 1000.0
    case .fadein(let fade): return elapsed < Double(fade.durationMs) / 1000.0
    case .translate(let t): return elapsed < Double(t.durationMs) / 1000.0
    }
  }
}
