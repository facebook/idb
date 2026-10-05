/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Foundation
import XCTest

final class SimulatorDisplayConfigurationTests: XCTestCase {
  private func display(
    _ id: String, _ activity: SimulatorDisplayActivity = .active, name: String? = nil, rotation: SimulatorDisplayRotation = .upright
  ) -> SimulatorDisplay {
    SimulatorDisplay(
      uniqueID: id, name: name ?? id, activity: activity, isPrimary: false, isIntegrated: true,
      bounds: CGRect(x: 0, y: 0, width: 1200, height: 800), scale: 2, rotation: rotation)
  }

  private var cover: SimulatorDisplayReport { .displays([display("cover"), display("inner", .inactive)]) }
  private var inner: SimulatorDisplayReport { .displays([display("cover", .inactive), display("inner")]) }

  // MARK: - Generations

  func testRepeatedReportKeepsItsGeneration() throws {
    let tracker = DisplayConfigurationTracker()
    let first = try tracker.observe(cover)
    let second = try tracker.observe(cover)
    XCTAssertEqual(first, SimulatorDisplayConfiguration(generation: 1, displays: [display("cover"), display("inner", .inactive)], active: .identified(display("cover")), phase: .settled))
    XCTAssertEqual(second, first)
  }

  func testFoldTransitionsWithinTheOutgoingGenerationThenSettlesOnTheNext() throws {
    let tracker = DisplayConfigurationTracker()
    let before = try tracker.observe(cover)
    let transitioning = try tracker.observe(.transitioning)
    let after = try tracker.observe(inner)
    XCTAssertEqual(transitioning, SimulatorDisplayConfiguration(generation: 1, displays: before.displays, active: before.active, phase: .transitioning))
    XCTAssertEqual(after.generation, 2)
    XCTAssertEqual(after.active, .identified(display("inner")))
    XCTAssertEqual(after.phase, .settled)
  }

  func testTransitionThatSettlesWhereItStartedKeepsItsGeneration() throws {
    let tracker = DisplayConfigurationTracker()
    _ = try tracker.observe(cover)
    _ = try tracker.observe(.transitioning)
    XCTAssertEqual(try tracker.observe(cover).generation, 1)
  }

  func testInterfaceRotationAdvancesTheGeneration() throws {
    let tracker = DisplayConfigurationTracker()
    _ = try tracker.observe(.displays([display("lcd")]))
    let rotated = try tracker.observe(.displays([display("lcd", rotation: .clockwise)]))
    XCTAssertEqual(rotated.generation, 2)
    XCTAssertEqual(rotated.active, .identified(display("lcd", rotation: .clockwise)))
  }

  func testRenamedDisplayKeepsItsGeneration() throws {
    let tracker = DisplayConfigurationTracker()
    _ = try tracker.observe(.displays([display("lcd")]))
    let renamed = try tracker.observe(.displays([display("lcd", name: "LCD")]))
    XCTAssertEqual(renamed.generation, 1)
    XCTAssertEqual(renamed.displays, [display("lcd", name: "LCD")])
  }

  func testLegacyGeometryChangeAdvancesTheGeneration() throws {
    let tracker = DisplayConfigurationTracker()
    let upright = try tracker.observe(.legacy(integrated: [display("lcd").geometry]))
    let rotated = try tracker.observe(.legacy(integrated: [display("lcd", rotation: .clockwise).geometry]))
    XCTAssertEqual(upright, SimulatorDisplayConfiguration(generation: 1, displays: [], active: .unidentified(display("lcd").geometry), phase: .settled))
    XCTAssertEqual(rotated.generation, 2)
  }

  func testUnresolvableActiveDisplayIsSettledWithoutOne() throws {
    let tracker = DisplayConfigurationTracker()
    let configuration = try tracker.observe(.displays([display("cover", .inactive), display("inner", .inactive)]))
    XCTAssertEqual(configuration.active, .unresolved)
    XCTAssertEqual(configuration.displays.count, 2)
  }

  func testActiveDisplayIsTheIdentifiedOne() throws {
    let configuration = try DisplayConfigurationTracker().observe(cover)
    XCTAssertEqual(try configuration.activeDisplay(), display("cover"))
    XCTAssertEqual(try configuration.activeGeometry(), display("cover").geometry)
  }

  func testLegacyDisplayHasGeometryButNoIdentity() throws {
    let configuration = try DisplayConfigurationTracker().observe(.legacy(integrated: [display("lcd").geometry]))
    XCTAssertEqual(try configuration.activeGeometry(), display("lcd").geometry)
    XCTAssertThrowsError(try configuration.activeDisplay()) { error in
      guard case SimulatorDisplayInteractionError.unsupportedCapability = error else { return XCTFail("unexpected error: \(error)") }
    }
  }

  func testSeveralLegacyDisplaysAreUnknown() throws {
    let geometry = display("lcd").geometry
    let configuration = try DisplayConfigurationTracker().observe(.legacy(integrated: [geometry, geometry]))
    XCTAssertEqual(configuration.active, .unknown)
    XCTAssertThrowsError(try configuration.activeGeometry()) { error in
      guard case SimulatorDisplayInteractionError.unsupportedCapability = error else { return XCTFail("unexpected error: \(error)") }
    }
  }

  func testNoActiveDisplayIsCurrentState() throws {
    let configuration = try DisplayConfigurationTracker().observe(.displays([display("cover", .inactive), display("inner", .inactive)]))
    XCTAssertThrowsError(try configuration.activeGeometry()) { error in
      guard case SimulatorDisplayError.noActiveIntegratedDisplay = error else { return XCTFail("unexpected error: \(error)") }
    }
  }

  func testSeveralActiveDisplaysAreCurrentState() throws {
    let configuration = try DisplayConfigurationTracker().observe(.displays([display("cover"), display("inner")]))
    XCTAssertThrowsError(try configuration.activeDisplay()) { error in
      guard case let SimulatorDisplayError.ambiguousActiveDisplays(identities) = error else { return XCTFail("unexpected error: \(error)") }
      XCTAssertEqual(identities, ["cover", "inner"])
    }
  }

  func testTransitioningConfigurationHasNoActiveDisplayYet() throws {
    let tracker = DisplayConfigurationTracker()
    _ = try tracker.observe(cover)
    let configuration = try tracker.observe(.transitioning)
    XCTAssertThrowsError(try configuration.activeDisplay()) { error in
      guard case SimulatorDisplayError.transitioning = error else { return XCTFail("unexpected error: \(error)") }
    }
  }

  func testFailedReadThrowsAndLeavesTheGenerationAlone() throws {
    let tracker = DisplayConfigurationTracker()
    _ = try tracker.observe(cover)
    XCTAssertThrowsError(try tracker.observe(.failed(.timedOut))) { error in
      XCTAssertEqual(error as? SimulatorCoreDeviceError, .timedOut)
    }
    XCTAssertEqual(try tracker.observe(cover).generation, 1)
  }

  // MARK: - Settled reads

  func testSettledConfigurationWaitsOutATransition() async throws {
    let displays = DisplayCommandsDouble([.success(.transitioning), .success(.transitioning), .success(inner)])
    let configuration = try await displays.settledConfiguration(within: .seconds(1))
    XCTAssertEqual(configuration.phase, .settled)
    XCTAssertEqual(configuration.active, .identified(display("inner")))
    XCTAssertEqual(displays.reads, 3)
  }

  func testSettledConfigurationReportsATransitionThatOutlastsTheTimeout() async throws {
    let displays = DisplayCommandsDouble([.success(cover), .success(.transitioning)])
    _ = try await displays.settledConfiguration(within: .zero)
    let configuration = try await displays.settledConfiguration(within: .milliseconds(20))
    XCTAssertEqual(configuration.phase, .transitioning)
    XCTAssertEqual(configuration.active, .identified(display("cover")))
  }

  func testSettledConfigurationThrowsAFailedRead() async {
    let displays = DisplayCommandsDouble([.success(.failed(.timedOut))])
    do {
      _ = try await displays.settledConfiguration(within: .seconds(1))
      XCTFail("Expected the read's failure")
    } catch {
      XCTAssertEqual(error as? SimulatorCoreDeviceError, .timedOut)
    }
  }

  func testRoutedReadsShareGenerations() async throws {
    let displays = DisplayCommandsDouble([.success(cover), .success(inner), .success(inner)])
    _ = try await displays.currentDisplay()
    _ = try await displays.currentDisplay()
    let configuration = try await displays.settledConfiguration(within: .zero)
    XCTAssertEqual(configuration.generation, 2)
  }

  // MARK: - Stream

  func testStreamReplaysTheCurrentConfigurationThenFollowsChangedPushes() async {
    let (pushes, push) = AsyncThrowingStream<SimulatorDisplayReport, Error>.makeStream()
    push.yield(cover)
    push.yield(.transitioning)
    push.yield(inner)
    push.yield(inner)
    push.finish()
    let displays = DisplayCommandsDouble([.success(cover), .success(inner)], pushes: pushes)
    let configurations = await collect(displays.followConfigurations(), count: 3)
    XCTAssertEqual(configurations.map(\.generation), [1, 1, 2])
    XCTAssertEqual(configurations.map(\.phase), [.settled, .transitioning, .settled])
  }

  func testStreamPollsWhenPushesAreUnavailable() async {
    let displays = DisplayCommandsDouble([.success(cover), .success(inner)])
    let configurations = await collect(displays.followConfigurations(polling: .milliseconds(1)), count: 2)
    XCTAssertEqual(configurations.map(\.generation), [1, 2])
  }

  func testStreamSkipsAFailedFirstRead() async {
    let (pushes, push) = AsyncThrowingStream<SimulatorDisplayReport, Error>.makeStream()
    push.yield(cover)
    push.finish()
    let displays = DisplayCommandsDouble([.success(.failed(.timedOut)), .success(cover)], pushes: pushes)
    let configurations = await collect(displays.followConfigurations(), count: 1)
    XCTAssertEqual(configurations.map(\.active), [.identified(display("cover"))])
  }

  /// The first `count` configurations; the stream polls forever, so the test hangs if fewer arrive.
  private func collect(_ stream: AsyncStream<SimulatorDisplayConfiguration>, count: Int) async -> [SimulatorDisplayConfiguration] {
    var collected: [SimulatorDisplayConfiguration] = []
    for await configuration in stream {
      collected.append(configuration)
      if collected.count == count { break }
    }
    return collected
  }
}
