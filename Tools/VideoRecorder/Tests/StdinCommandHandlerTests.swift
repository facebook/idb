/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBSimulatorControl
@testable import SimulatorVideo
import Testing

@Suite struct StdinCommandHandlerTests {
  @MainActor
  private func makeHandler(screenshotDir: String? = nil) -> StdinCommandHandler {
    let renderer = OverlayRenderer(width: 100, height: 100)
    let logger = FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: false, withDebugLogging: false)
    return StdinCommandHandler(
      renderer: renderer,
      screenshotDir: screenshotDir,
      logger: logger
    )
  }

  @MainActor
  @Test func testOverlayCommandParsed() async {
    let handler = makeHandler()
    let json = """
      {"method":"overlay","params":{"overlays":[{"circle":{"x":50,"y":50,"radius":10,"rgba":[64,64,64,0.5]}}]}}
      """
    await handler.handleLine(json)
  }

  @MainActor
  @Test func testEmptyOverlayClearsState() async {
    let handler = makeHandler()
    await handler.handleLine(
      """
      {"method":"overlay","params":{"overlays":[{"circle":{"x":50,"y":50,"radius":10,"rgba":[255,0,0,1]}}]}}
      """)
    await handler.handleLine(
      """
      {"method":"overlay","params":{"overlays":[]}}
      """)
  }

  @MainActor
  @Test func testShutdownSetsFlag() async {
    let handler = makeHandler()
    #expect(!(handler.shutdownRequested))
    await handler.handleLine("{\"method\":\"shutdown\"}")
    #expect(handler.shutdownRequested)
  }

  @MainActor
  @Test func testChapterCommandParsed() async {
    let handler = makeHandler()
    await handler.handleLine(
      """
      {"method":"chapter","params":{"text":"Step 1: App Launch"}}
      """)
  }

  @MainActor
  @Test func testChapterCommandWithoutTextDoesNotCrash() async {
    let handler = makeHandler()
    await handler.handleLine("{\"method\":\"chapter\"}")
    await handler.handleLine("{\"method\":\"chapter\",\"params\":{}}")
    await handler.handleLine("{\"method\":\"chapter\",\"params\":{\"text\":\"\"}}")
  }

  @MainActor
  @Test func testUnknownMethodDoesNotCrash() async {
    let handler = makeHandler()
    await handler.handleLine("{\"method\":\"unknown_method\"}")
  }

  @MainActor
  @Test func testInvalidJSONDoesNotCrash() async {
    let handler = makeHandler()
    await handler.handleLine("this is not json")
    await handler.handleLine("")
    await handler.handleLine("{}")
  }

  @MainActor
  @Test func testForceKeyframeWithoutVideoStreamDoesNotCrash() async {
    let handler = makeHandler()
    await handler.handleLine("{\"method\":\"force_keyframe\"}")
    #expect(handler.shutdownRequested == false)
  }

  @MainActor
  @Test func testScreenshotWithoutVideoStreamDoesNotCrash() async {
    let handler = makeHandler(screenshotDir: NSTemporaryDirectory())
    await handler.handleLine("{\"method\":\"screenshot\",\"params\":{\"index\":0}}")
  }

  @MainActor
  @Test func testScreenshotWithoutDirDoesNotCrash() async {
    let handler = makeHandler(screenshotDir: nil)
    await handler.handleLine("{\"method\":\"screenshot\",\"params\":{\"index\":0}}")
  }

  // MARK: - bar command

  @MainActor
  @Test func testBarTextSetsContent() async {
    let handler = makeHandler()
    await handler.handleLine("{\"method\":\"bar\",\"params\":{\"position\":\"bottom\",\"content\":\"text\",\"text\":\"waitLeft=12.3s\"}}")
    #expect(handler.renderer.barContent["bottom"] == .text("waitLeft=12.3s"))
  }

  @MainActor
  @Test func testBarTextEmptyStringDrawsEmptyBar() async {
    let handler = makeHandler()
    await handler.handleLine("{\"method\":\"bar\",\"params\":{\"position\":\"bottom\",\"content\":\"text\",\"text\":\"\"}}")
    #expect(handler.renderer.barContent["bottom"] == .text(""))
  }

  @MainActor
  @Test func testBarTextWithoutTextFieldDefaultsToEmpty() async {
    let handler = makeHandler()
    await handler.handleLine("{\"method\":\"bar\",\"params\":{\"position\":\"bottom\",\"content\":\"text\"}}")
    #expect(handler.renderer.barContent["bottom"] == .text(""))
  }

  @MainActor
  @Test func testBarStatsSetsStatsMode() async {
    let handler = makeHandler()
    await handler.handleLine("{\"method\":\"bar\",\"params\":{\"position\":\"bottom\",\"content\":\"stats\"}}")
    #expect(handler.renderer.barContent["bottom"] == .stats)
  }

  @MainActor
  @Test func testBarNullContentHidesBar() async {
    let handler = makeHandler()
    await handler.handleLine("{\"method\":\"bar\",\"params\":{\"position\":\"bottom\",\"content\":\"text\",\"text\":\"first\"}}")
    #expect(handler.renderer.barContent["bottom"] == .text("first"))
    await handler.handleLine("{\"method\":\"bar\",\"params\":{\"position\":\"bottom\",\"content\":null}}")
    #expect(handler.renderer.barContent["bottom"] == .hidden)
  }

  @MainActor
  @Test func testBarOmittedContentHidesBar() async {
    let handler = makeHandler()
    await handler.handleLine("{\"method\":\"bar\",\"params\":{\"position\":\"bottom\",\"content\":\"text\",\"text\":\"first\"}}")
    await handler.handleLine("{\"method\":\"bar\",\"params\":{\"position\":\"bottom\"}}")
    #expect(handler.renderer.barContent["bottom"] == .hidden)
  }

  @MainActor
  @Test func testBarMissingPositionIgnored() async {
    let handler = makeHandler()
    await handler.handleLine("{\"method\":\"bar\",\"params\":{\"content\":\"text\",\"text\":\"no position\"}}")
    #expect(handler.renderer.barContent.isEmpty)
  }

  @MainActor
  @Test func testBarTopAndBottomIndependent() async {
    let handler = makeHandler()
    await handler.handleLine("{\"method\":\"bar\",\"params\":{\"position\":\"top\",\"content\":\"text\",\"text\":\"top text\"}}")
    await handler.handleLine("{\"method\":\"bar\",\"params\":{\"position\":\"bottom\",\"content\":\"text\",\"text\":\"bottom text\"}}")
    #expect(handler.renderer.barContent["top"] == .text("top text"))
    #expect(handler.renderer.barContent["bottom"] == .text("bottom text"))
    await handler.handleLine("{\"method\":\"bar\",\"params\":{\"position\":\"top\",\"content\":null}}")
    #expect(handler.renderer.barContent["top"] == .hidden)
    #expect(handler.renderer.barContent["bottom"] == .text("bottom text"))
  }

  @MainActor
  @Test func testBarReplacesPreviousContent() async {
    let handler = makeHandler()
    await handler.handleLine("{\"method\":\"bar\",\"params\":{\"position\":\"bottom\",\"content\":\"text\",\"text\":\"step 1\"}}")
    await handler.handleLine("{\"method\":\"bar\",\"params\":{\"position\":\"bottom\",\"content\":\"text\",\"text\":\"step 2\"}}")
    #expect(handler.renderer.barContent["bottom"] == .text("step 2"))
  }

  @MainActor
  @Test func testBarTextToStatsTransition() async {
    let handler = makeHandler()
    await handler.handleLine("{\"method\":\"bar\",\"params\":{\"position\":\"bottom\",\"content\":\"text\",\"text\":\"diagnostic\"}}")
    #expect(handler.renderer.barContent["bottom"] == .text("diagnostic"))
    await handler.handleLine("{\"method\":\"bar\",\"params\":{\"position\":\"bottom\",\"content\":\"stats\"}}")
    #expect(handler.renderer.barContent["bottom"] == .stats)
  }

  // MARK: - Bar fit param

  @MainActor
  @Test func testBarFitTrueIsAppliedToRenderer() async {
    let handler = makeHandler()
    await handler.handleLine(
      "{\"method\":\"bar\",\"params\":{\"position\":\"bottom\",\"content\":\"text\",\"text\":\"foo\",\"fit\":true}}")
    #expect(handler.renderer.barFit["bottom"] == true)
    #expect(handler.renderer.barContent["bottom"] == .text("foo"))
  }

  @MainActor
  @Test func testBarFitFalseIsAppliedToRenderer() async {
    let handler = makeHandler()
    handler.renderer.setBarFit(true, position: "bottom")
    await handler.handleLine(
      "{\"method\":\"bar\",\"params\":{\"position\":\"bottom\",\"content\":\"text\",\"text\":\"foo\",\"fit\":false}}")
    #expect(handler.renderer.barFit["bottom"] == false)
  }

  @MainActor
  @Test func testBarFitOmittedDoesNotChangeRendererFit() async {
    let handler = makeHandler()
    handler.renderer.setBarFit(true, position: "bottom")
    await handler.handleLine(
      "{\"method\":\"bar\",\"params\":{\"position\":\"bottom\",\"content\":\"text\",\"text\":\"foo\"}}")
    #expect(handler.renderer.barFit["bottom"] == true)
  }

  @MainActor
  @Test func testBarFitPersistsAcrossContentTypeChange() async {
    let handler = makeHandler()
    await handler.handleLine(
      "{\"method\":\"bar\",\"params\":{\"position\":\"bottom\",\"content\":\"text\",\"text\":\"foo\",\"fit\":true}}")
    await handler.handleLine(
      "{\"method\":\"bar\",\"params\":{\"position\":\"bottom\",\"content\":\"stats\"}}")
    #expect(handler.renderer.barContent["bottom"] == .stats)
    #expect(handler.renderer.barFit["bottom"] == true)
  }

  // MARK: - Deprecated bottomStatus/topStatus aliases

  @MainActor
  @Test func testDeprecatedBottomStatusMapsToBar() async {
    let handler = makeHandler()
    await handler.handleLine("{\"method\":\"bottomStatus\",\"params\":{\"text\":\"wait text\"}}")
    #expect(handler.renderer.barContent["bottom"] == .text("wait text"))
  }

  @MainActor
  @Test func testDeprecatedBottomStatusNullHidesBar() async {
    let handler = makeHandler()
    await handler.handleLine("{\"method\":\"bottomStatus\",\"params\":{\"text\":\"first\"}}")
    await handler.handleLine("{\"method\":\"bottomStatus\",\"params\":{\"text\":null}}")
    #expect(handler.renderer.barContent["bottom"] == .hidden)
  }

  @MainActor
  @Test func testDeprecatedTopStatusMapsToBar() async {
    let handler = makeHandler()
    await handler.handleLine("{\"method\":\"topStatus\",\"params\":{\"text\":\"assertion visible\"}}")
    #expect(handler.renderer.barContent["top"] == .text("assertion visible"))
  }

  @MainActor
  @Test func testDeprecatedTopStatusNullHidesBar() async {
    let handler = makeHandler()
    await handler.handleLine("{\"method\":\"topStatus\",\"params\":{\"text\":\"first\"}}")
    await handler.handleLine("{\"method\":\"topStatus\",\"params\":{\"text\":null}}")
    #expect(handler.renderer.barContent["top"] == .hidden)
  }

  // MARK: - StdinCommand Parser Tests

  // swiftlint:disable force_unwrapping

  @Test func testParseOverlayCommand() throws {
    let json = """
      {"method":"overlay","params":{"overlays":[{"circle":{"x":50,"y":74,"radius":10,"rgba":[64,64,64,0.5],"effect":{"fadeout":{"durationMs":350}}}}]}}
      """
    let cmd = try JSONDecoder().decode(StdinCommand.self, from: json.data(using: .utf8)!)
    guard case .overlay(let overlays) = cmd else {
      Issue.record("expected an overlay command, got \(cmd)")
      return
    }
    #expect(overlays.count == 1)
  }

  @Test func testParseScreenshotCommand() throws {
    let json = """
      {"method":"screenshot","params":{"index":5}}
      """
    let cmd = try JSONDecoder().decode(StdinCommand.self, from: json.data(using: .utf8)!)
    guard case .screenshot(let index) = cmd else {
      Issue.record("expected a screenshot command, got \(cmd)")
      return
    }
    #expect(index == 5)
  }

  @Test func testParseChapterCommand() throws {
    let json = """
      {"method":"chapter","params":{"text":"Login Screen"}}
      """
    let cmd = try JSONDecoder().decode(StdinCommand.self, from: json.data(using: .utf8)!)
    guard case .chapter(let text) = cmd else {
      Issue.record("expected a chapter command, got \(cmd)")
      return
    }
    #expect(text == "Login Screen")
  }

  @Test func testParseShutdownCommand() throws {
    let json = """
      {"method":"shutdown"}
      """
    let cmd = try JSONDecoder().decode(StdinCommand.self, from: json.data(using: .utf8)!)
    guard case .shutdown = cmd else {
      Issue.record("expected a shutdown command, got \(cmd)")
      return
    }
  }

  @Test func testParseBarCommand() throws {
    let json = """
      {"method":"bar","params":{"position":"bottom","content":"text","text":"hello"}}
      """
    let cmd = try JSONDecoder().decode(StdinCommand.self, from: json.data(using: .utf8)!)
    guard case .bar(let position, let content, let fit) = cmd else {
      Issue.record("expected a bar command, got \(cmd)")
      return
    }
    #expect(position == "bottom")
    #expect(content == .resolved(.text("hello")))
    #expect(fit == nil)
  }

  @Test func testParseBarStatsCommand() throws {
    let json = """
      {"method":"bar","params":{"position":"top","content":"stats"}}
      """
    let cmd = try JSONDecoder().decode(StdinCommand.self, from: json.data(using: .utf8)!)
    guard case .bar(let position, let content, _) = cmd else {
      Issue.record("expected a bar command, got \(cmd)")
      return
    }
    #expect(position == "top")
    #expect(content == .resolved(.stats))
  }

  @Test func testParseCommandWithNoParams() throws {
    let json = """
      {"method":"overlay"}
      """
    let cmd = try JSONDecoder().decode(StdinCommand.self, from: json.data(using: .utf8)!)
    guard case .overlay(let overlays) = cmd else {
      Issue.record("expected an overlay command, got \(cmd)")
      return
    }
    #expect(overlays.isEmpty)
  }

  @Test func testParseCommandWithEmptyOverlays() throws {
    let json = """
      {"method":"overlay","params":{"overlays":[]}}
      """
    let cmd = try JSONDecoder().decode(StdinCommand.self, from: json.data(using: .utf8)!)
    guard case .overlay(let overlays) = cmd else {
      Issue.record("expected an overlay command, got \(cmd)")
      return
    }
    #expect(overlays.isEmpty)
  }

  @Test func testParseCommandWithMultipleOverlays() throws {
    let json = """
      {"method":"overlay","params":{"overlays":[{"circle":{"x":10,"y":20,"radius":5,"rgba":[255,0,0,1]}},{"rectangle":{"x":0,"y":0,"width":-1,"height":24,"rgba":[64,64,64,1]}},{"label":{"text":"Step: Login","padding":4,"font":"Monaco 8"}}]}}
      """
    let cmd = try JSONDecoder().decode(StdinCommand.self, from: json.data(using: .utf8)!)
    guard case .overlay(let overlays) = cmd else {
      Issue.record("expected an overlay command, got \(cmd)")
      return
    }
    #expect(overlays.count == 3)
  }

  @Test func testInvalidJSONReturnsDecodingError() async {
    let json = "not valid json"
    #expect(throws: (any Error).self) { try JSONDecoder().decode(StdinCommand.self, from: json.data(using: .utf8)!) }
  }

  // swiftlint:enable force_unwrapping
}
