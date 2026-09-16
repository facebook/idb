/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBSimulatorControl
import Foundation
@testable import SimulatorVideo
import Testing

/// Records every logged line, so the diagnostics a command emits are assertable. The `screenshot`
/// and `chapter` paths have no other observable effect without a live `SimulatorVideoStream`, so
/// this is what distinguishes "the command parsed and dispatched" from "the line was rejected".
///
/// `@unchecked Sendable` is sound because every access to `recorded` is behind `lock`.
private final class RecordingLogger: NSObject, FBControlCoreLogger, @unchecked Sendable {
  /// The prefix of the decode-failure diagnostic. `DecodingError`'s own wording is interpolated
  /// after it and is not part of the wire protocol, so assertions elide it.
  static let decodeFailure = "Failed to decode stdin command:"

  private let lock = NSLock()
  private var recorded: [String] = []

  var name: String? { nil }
  var level: FBControlCoreLogLevel { .info }

  var messages: [String] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }

  /// `messages` with each decode failure collapsed to `decodeFailure`.
  var normalizedMessages: [String] {
    messages.map { $0.hasPrefix(Self.decodeFailure) ? Self.decodeFailure : $0 }
  }

  @discardableResult
  func log(_ message: String) -> any FBControlCoreLogger {
    lock.lock()
    defer { lock.unlock() }
    recorded.append(message)
    return self
  }

  func info() -> any FBControlCoreLogger { self }
  func debug() -> any FBControlCoreLogger { self }
  func error() -> any FBControlCoreLogger { self }
  func withName(_ name: String) -> any FBControlCoreLogger { self }
  func withDateFormatEnabled(_ enabled: Bool) -> any FBControlCoreLogger { self }
}

/// Characterizes the stdin JSON wire protocol as `handleLine` implements it: which lines decode,
/// which are rejected wholesale, and what each accepted command does to renderer state and the log.
@Suite @MainActor struct StdinWireProtocolTests {
  private func makeHandler(screenshotDir: String? = nil) -> (StdinCommandHandler, RecordingLogger) {
    let logger = RecordingLogger()
    let handler = StdinCommandHandler(
      renderer: OverlayRenderer(width: 100, height: 100),
      screenshotDir: screenshotDir,
      logger: logger
    )
    return (handler, logger)
  }

  private static let circle = #"{"circle":{"x":50,"y":50,"radius":10,"rgba":[64,64,64,0.5]}}"#

  // MARK: - Line framing

  @Test func testEmptyLineIsIgnored() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine("")
    #expect(logger.messages.isEmpty)
    #expect(!handler.shutdownRequested)
  }

  @Test func testWhitespaceOnlyLineIsIgnored() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine("   \t \n ")
    #expect(logger.messages.isEmpty)
  }

  @Test func testSurroundingWhitespaceIsTrimmedBeforeDecoding() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine("\t  {\"method\":\"shutdown\"}  \n")
    #expect(handler.shutdownRequested)
    #expect(logger.normalizedMessages == ["Shutdown requested via stdin"])
  }

  // MARK: - Rejected lines

  @Test func testNonJSONLineIsRejected() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine("this is not json")
    #expect(logger.normalizedMessages == [RecordingLogger.decodeFailure])
  }

  @Test func testObjectWithoutMethodIsRejected() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine("{}")
    #expect(logger.normalizedMessages == [RecordingLogger.decodeFailure])
  }

  /// A `params` that is not an object rejects the line, rather than reading as absent params — the
  /// `shutdown` each of these lines names never runs.
  @Test func testNonObjectParamsIsRejected() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"shutdown","params":5}"#)
    await handler.handleLine(#"{"method":"shutdown","params":[]}"#)
    await handler.handleLine(#"{"method":"shutdown","params":"bottom"}"#)
    #expect(!handler.shutdownRequested)
    #expect(logger.normalizedMessages == Array(repeating: RecordingLogger.decodeFailure, count: 3))
  }

  @Test func testJSONArrayIsRejected() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine("[{\"method\":\"shutdown\"}]")
    #expect(logger.normalizedMessages == [RecordingLogger.decodeFailure])
    #expect(!handler.shutdownRequested)
  }

  @Test func testTwoObjectsOnOneLineAreRejected() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine("{\"method\":\"shutdown\"}{\"method\":\"shutdown\"}")
    #expect(logger.normalizedMessages == [RecordingLogger.decodeFailure])
    #expect(!handler.shutdownRequested)
  }

  @Test func testUnknownOverlayShapeTagIsRejected() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"overlay","params":{"overlays":[{"triangle":{"x":1}}]}}"#)
    #expect(logger.normalizedMessages == [RecordingLogger.decodeFailure])
  }

  @Test func testUnknownOverlayEffectTagIsRejected() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(
      #"{"method":"overlay","params":{"overlays":[{"circle":{"x":1,"y":2,"radius":3,"rgba":[1,1,1,1],"effect":{"explode":{"durationMs":10}}}}]}}"#)
    #expect(logger.normalizedMessages == [RecordingLogger.decodeFailure])
  }

  @Test func testWronglyTypedOverlaysIsRejected() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"overlay","params":{"overlays":{}}}"#)
    #expect(logger.normalizedMessages == [RecordingLogger.decodeFailure])
  }

  @Test func testFractionalIndexIsRejected() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"screenshot","params":{"index":5.5}}"#)
    #expect(logger.normalizedMessages == [RecordingLogger.decodeFailure])
  }

  // MARK: - The whole line is decoded before the method is read

  /// A field the method never reads still has to decode: `params` is one type covering every
  /// command, so a wrongly-typed `index` costs the `shutdown` that would otherwise have happened.
  @Test func testWronglyTypedIrrelevantFieldDropsTheWholeCommand() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"shutdown","params":{"index":"nope"}}"#)
    #expect(logger.normalizedMessages == [RecordingLogger.decodeFailure])
    #expect(!handler.shutdownRequested)
  }

  @Test func testWronglyTypedFitDropsTheWholeBarCommand() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"bar","params":{"position":"bottom","content":"text","text":"x","fit":"yes"}}"#)
    #expect(logger.normalizedMessages == [RecordingLogger.decodeFailure])
    #expect(handler.renderer.barContent.isEmpty)
  }

  // MARK: - Accepted shorthands

  @Test func testUnknownTopLevelKeysAreIgnored() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"shutdown","id":7,"comment":"ignored"}"#)
    #expect(handler.shutdownRequested)
    #expect(logger.normalizedMessages == ["Shutdown requested via stdin"])
  }

  @Test func testUnknownParamsKeysAreIgnored() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"shutdown","params":{"bogus":1}}"#)
    #expect(handler.shutdownRequested)
    #expect(logger.normalizedMessages == ["Shutdown requested via stdin"])
  }

  @Test func testNullParamsIsTreatedAsAbsentParams() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"bar","params":null}"#)
    #expect(logger.normalizedMessages == ["bar command missing position"])
  }

  @Test func testNullOverlaysIsTreatedAsAnEmptyOverlayList() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"overlay","params":{"overlays":null}}"#)
    #expect(logger.normalizedMessages == ["Overlay cleared"])
  }

  @Test func testIntegralFloatIndexIsAccepted() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"screenshot","params":{"index":5.0}}"#)
    #expect(logger.normalizedMessages == ["Screenshot requested but no --screenshot-dir configured"])
  }

  /// A repeated key is not an error, and the first occurrence wins — the later `shutdown` is
  /// discarded rather than overriding the `chapter` in front of it.
  @Test func testDuplicateMethodKeysTakeTheFirstValue() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"chapter","method":"shutdown"}"#)
    #expect(!handler.shutdownRequested)
    #expect(logger.normalizedMessages == ["Chapter command missing text"])
  }

  @Test func testMethodNamesAreCaseSensitive() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"Shutdown"}"#)
    #expect(!handler.shutdownRequested)
    #expect(logger.normalizedMessages == ["Unknown stdin command: Shutdown"])
  }

  @Test func testUnknownMethodIsReported() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"frobnicate","params":{"index":1}}"#)
    #expect(logger.normalizedMessages == ["Unknown stdin command: frobnicate"])
  }

  // MARK: - overlay

  @Test func testPopulatedOverlayIsReportedWithItsShapeCount() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"overlay","params":{"overlays":[\#(Self.circle),\#(Self.circle)]}}"#)
    #expect(logger.normalizedMessages == ["Overlay updated with 2 shapes"])
  }

  @Test func testOverlayWithoutParamsClears() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"overlay"}"#)
    #expect(logger.normalizedMessages == ["Overlay cleared"])
  }

  /// `clear()` wipes the shape buffer but not the bars, so a bar set earlier survives an
  /// overlay clear and is re-rendered rather than dropped.
  @Test func testEmptyOverlayPreservesBarContent() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"bar","params":{"position":"bottom","content":"text","text":"kept"}}"#)
    await handler.handleLine(#"{"method":"overlay","params":{"overlays":[]}}"#)
    #expect(handler.renderer.barContent["bottom"] == .text("kept"))
    #expect(logger.normalizedMessages.last == "Overlay cleared")
  }

  // MARK: - screenshot

  @Test func testScreenshotWithoutADirectoryIsReported() async {
    let (handler, logger) = makeHandler(screenshotDir: nil)
    await handler.handleLine(#"{"method":"screenshot","params":{"index":3}}"#)
    #expect(logger.normalizedMessages == ["Screenshot requested but no --screenshot-dir configured"])
  }

  @Test func testScreenshotWithoutAStreamIsReported() async {
    let (handler, logger) = makeHandler(screenshotDir: NSTemporaryDirectory())
    await handler.handleLine(#"{"method":"screenshot","params":{"index":3}}"#)
    #expect(logger.normalizedMessages == ["Screenshot requested but no video stream available"])
  }

  @Test func testScreenshotWithoutParamsIsAccepted() async {
    let (handler, logger) = makeHandler(screenshotDir: NSTemporaryDirectory())
    await handler.handleLine(#"{"method":"screenshot"}"#)
    #expect(logger.normalizedMessages == ["Screenshot requested but no video stream available"])
  }

  // MARK: - chapter

  @Test func testChapterWithTextIsDispatched() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"chapter","params":{"text":"Login Screen"}}"#)
    #expect(logger.normalizedMessages == ["Chapter command received but no video stream available"])
  }

  @Test func testChapterWithoutParamsIsReportedAsMissingText() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"chapter"}"#)
    #expect(logger.normalizedMessages == ["Chapter command missing text"])
  }

  @Test func testChapterWithNullTextIsReportedAsMissingText() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"chapter","params":{"text":null}}"#)
    #expect(logger.normalizedMessages == ["Chapter command missing text"])
  }

  @Test func testChapterWithEmptyTextIsReportedAsMissingText() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"chapter","params":{"text":""}}"#)
    #expect(logger.normalizedMessages == ["Chapter command missing text"])
  }

  // MARK: - bar

  @Test func testBarWithoutPositionIsIgnored() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"bar","params":{"content":"text","text":"x"}}"#)
    #expect(handler.renderer.barContent.isEmpty)
    #expect(logger.normalizedMessages == ["bar command missing position"])
  }

  /// The position is checked before the content, so an unrecognized content type is not even
  /// reported when the position is also absent.
  @Test func testBarWithoutPositionOutranksUnrecognizedContent() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"bar","params":{"content":"bogus"}}"#)
    #expect(logger.normalizedMessages == ["bar command missing position"])
  }

  @Test func testBarWithUnrecognizedContentIsIgnored() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"bar","params":{"position":"bottom","content":"TEXT"}}"#)
    #expect(handler.renderer.barContent.isEmpty)
    #expect(logger.normalizedMessages == ["bar command unknown content type: TEXT"])
  }

  @Test func testBarWithUnrecognizedContentLeavesPreviousContentIntact() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"bar","params":{"position":"bottom","content":"text","text":"first"}}"#)
    await handler.handleLine(#"{"method":"bar","params":{"position":"bottom","content":"marquee"}}"#)
    #expect(handler.renderer.barContent["bottom"] == .text("first"))
    #expect(logger.normalizedMessages.last == "bar command unknown content type: marquee")
  }

  /// The content is classified before the renderer is touched at all, so an unrecognized content
  /// type discards the `fit` that arrived with it instead of applying it to the bar it left alone.
  @Test func testBarUnrecognizedContentChangesNeitherContentNorFit() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"bar","params":{"position":"bottom","content":"text","text":"kept","fit":true}}"#)
    await handler.handleLine(#"{"method":"bar","params":{"position":"bottom","content":"marquee","fit":false}}"#)
    #expect(handler.renderer.barContent["bottom"] == .text("kept"))
    #expect(handler.renderer.barFit["bottom"] == true)
    #expect(logger.normalizedMessages.last == "bar command unknown content type: marquee")
  }

  @Test func testBarTextIsReportedWithItsContentAndFit() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"bar","params":{"position":"bottom","content":"text","text":"x","fit":true}}"#)
    #expect(handler.renderer.barContent["bottom"] == .text("x"))
    #expect(handler.renderer.barFit["bottom"] == true)
    #expect(logger.normalizedMessages == ["bar bottom set to text(\"x\") (fit=true)"])
  }

  @Test func testBarStatsIsReportedWithAnUnsetFit() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"bar","params":{"position":"bottom","content":"stats"}}"#)
    #expect(handler.renderer.barContent["bottom"] == .stats)
    #expect(logger.normalizedMessages == ["bar bottom set to stats (fit=false)"])
  }

  @Test func testBarNullContentHidesTheBar() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"bar","params":{"position":"bottom","content":null}}"#)
    #expect(handler.renderer.barContent["bottom"] == .hidden)
    #expect(logger.normalizedMessages == ["bar bottom set to hidden (fit=false)"])
  }

  /// An empty content string hides the bar, and the `text` alongside it is discarded rather
  /// than drawn as an empty bar.
  @Test func testBarEmptyContentStringHidesTheBar() async {
    let (handler, _) = makeHandler()
    await handler.handleLine(#"{"method":"bar","params":{"position":"bottom","content":"","text":"x"}}"#)
    #expect(handler.renderer.barContent["bottom"] == .hidden)
  }

  @Test func testBarTextWithoutATextFieldIsEmptyText() async {
    let (handler, _) = makeHandler()
    await handler.handleLine(#"{"method":"bar","params":{"position":"bottom","content":"text"}}"#)
    #expect(handler.renderer.barContent["bottom"] == .text(""))
  }

  /// The position is a free-form renderer key, not a closed set — an unrecognized one is stored
  /// rather than rejected.
  @Test func testBarAcceptsAnyPosition() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"bar","params":{"position":"middle","content":"text","text":"x"}}"#)
    #expect(handler.renderer.barContent["middle"] == .text("x"))
    #expect(logger.normalizedMessages == ["bar middle set to text(\"x\") (fit=false)"])
  }

  @Test func testBarFitOmittedRetainsThePreviousFit() async {
    let (handler, _) = makeHandler()
    await handler.handleLine(#"{"method":"bar","params":{"position":"bottom","content":"text","text":"x","fit":true}}"#)
    await handler.handleLine(#"{"method":"bar","params":{"position":"bottom","content":"stats"}}"#)
    #expect(handler.renderer.barFit["bottom"] == true)
  }

  @Test func testBarTextPreservesUnicode() async {
    let (handler, _) = makeHandler()
    await handler.handleLine(#"{"method":"bar","params":{"position":"bottom","content":"text","text":"café ☕ é"}}"#)
    #expect(handler.renderer.barContent["bottom"] == .text("café ☕ é"))
  }

  // MARK: - Deprecated bottomStatus / topStatus aliases

  @Test func testBottomStatusIsDeprecatedAndSetsTheBottomBar() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"bottomStatus","params":{"text":"waiting"}}"#)
    #expect(handler.renderer.barContent["bottom"] == .text("waiting"))
    #expect(
      logger.normalizedMessages == [
        "bottomStatus is deprecated; use {method:\"bar\", params:{position:\"bottom\", ...}}",
        "bar bottom set to text(\"waiting\") (fit=false)",
      ])
  }

  @Test func testTopStatusIsDeprecatedAndSetsTheTopBar() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine(#"{"method":"topStatus","params":{"text":"assertion visible"}}"#)
    #expect(handler.renderer.barContent["top"] == .text("assertion visible"))
    #expect(
      logger.normalizedMessages == [
        "topStatus is deprecated; use {method:\"bar\", params:{position:\"top\", ...}}",
        "bar top set to text(\"assertion visible\") (fit=false)",
      ])
  }

  @Test func testDeprecatedStatusWithoutTextHidesTheBar() async {
    let (handler, _) = makeHandler()
    await handler.handleLine(#"{"method":"bottomStatus"}"#)
    #expect(handler.renderer.barContent["bottom"] == .hidden)
  }

  @Test func testDeprecatedStatusWithNullTextHidesTheBar() async {
    let (handler, _) = makeHandler()
    await handler.handleLine(#"{"method":"bottomStatus","params":{"text":null}}"#)
    #expect(handler.renderer.barContent["bottom"] == .hidden)
  }

  @Test func testDeprecatedStatusWithEmptyTextDrawsAnEmptyBar() async {
    let (handler, _) = makeHandler()
    await handler.handleLine(#"{"method":"bottomStatus","params":{"text":""}}"#)
    #expect(handler.renderer.barContent["bottom"] == .text(""))
  }

  /// The alias hardcodes its position, so a `position` in its params is inert.
  @Test func testDeprecatedStatusIgnoresAPositionInItsParams() async {
    let (handler, _) = makeHandler()
    await handler.handleLine(#"{"method":"bottomStatus","params":{"position":"top","text":"x"}}"#)
    #expect(handler.renderer.barContent["bottom"] == .text("x"))
    #expect(handler.renderer.barContent["top"] == nil)
  }

  /// The alias forwards no `fit`, so one in its params never reaches the renderer.
  @Test func testDeprecatedStatusDropsAFitInItsParams() async {
    let (handler, _) = makeHandler()
    await handler.handleLine(#"{"method":"bottomStatus","params":{"text":"x","fit":true}}"#)
    #expect(handler.renderer.barFit["bottom"] == nil)
  }

  /// The alias maps only `text`, so a `content` in its params never selects stats mode.
  @Test func testDeprecatedStatusIgnoresAContentInItsParams() async {
    let (handler, _) = makeHandler()
    await handler.handleLine(#"{"method":"bottomStatus","params":{"content":"stats","text":"x"}}"#)
    #expect(handler.renderer.barContent["bottom"] == .text("x"))
  }

  // MARK: - shutdown

  @Test func testShutdownSetsTheFlagAndIsReported() async {
    let (handler, logger) = makeHandler()
    #expect(!handler.shutdownRequested)
    await handler.handleLine(#"{"method":"shutdown","params":{"text":"ignored"}}"#)
    #expect(handler.shutdownRequested)
    #expect(logger.normalizedMessages == ["Shutdown requested via stdin"])
  }

  /// Lines are applied in the order they arrive, so a command after a rejected line still runs.
  @Test func testARejectedLineDoesNotStopLaterLines() async {
    let (handler, logger) = makeHandler()
    await handler.handleLine("{oops")
    await handler.handleLine(#"{"method":"shutdown"}"#)
    #expect(handler.shutdownRequested)
    #expect(logger.normalizedMessages == [RecordingLogger.decodeFailure, "Shutdown requested via stdin"])
  }
}
