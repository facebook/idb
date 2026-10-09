/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import XCTest

/// Each read takes the next scripted orientation; the last one repeats.
private final class OrientationPoseDouble: PoseCommands {
  let displays: any DisplayCommands
  private var results: [Result<SimulatorDeviceOrientation, any Error>]
  private(set) var writes: [SimulatorDeviceOrientation] = []
  private(set) var reads = 0

  init(_ results: [Result<SimulatorDeviceOrientation, any Error>], displays: [SimulatorDisplayReport]) {
    self.results = results
    self.displays = DisplayCommandsDouble(displays.map { .success($0) })
  }

  func set(_ value: SimulatorDeviceOrientation) async throws {
    writes.append(value)
  }

  func current() async throws -> SimulatorDeviceOrientation {
    reads += 1
    return try (results.count > 1 ? results.removeFirst() : results[0]).get()
  }

  func reached(_ value: SimulatorDeviceOrientation, target: SimulatorDeviceOrientation) -> Bool { value == target }

  func pose(_ value: SimulatorDeviceOrientation) -> SimulatorPose { .orientation(value) }
}

final class SimulatorPoseConfirmationTests: XCTestCase {
  private let display = SimulatorDisplay(
    uniqueID: "inner", name: "inner", activity: .active, isPrimary: true, isIntegrated: true,
    bounds: CGRect(x: 0, y: 0, width: 1200, height: 800), scale: 2, rotation: .upright)

  func testReachedPoseReturnsTheSettledConfiguration() async throws {
    let poses = OrientationPoseDouble([.success(.landscapeLeft), .success(.faceUp), .success(.portrait)], displays: [.displays([display])])
    let configuration = try await poses.set(.portrait, confirmingWithin: .seconds(1), interval: .milliseconds(1))
    XCTAssertEqual(configuration, SimulatorDisplayConfiguration(generation: 1, displays: [display], active: .identified(display), phase: .settled))
    XCTAssertEqual(poses.writes, [.portrait])
    XCTAssertEqual(poses.reads, 3)
  }

  func testUnreachedPoseReportsTheLastReading() async {
    let poses = OrientationPoseDouble([.success(.landscapeLeft), .success(.faceUp)], displays: [.displays([display])])
    do {
      _ = try await poses.set(.portrait, confirmingWithin: .milliseconds(20), interval: .milliseconds(1))
      XCTFail("Expected the pose not to be reached")
    } catch {
      XCTAssertEqual(
        error as? SimulatorPoseConfirmationError, .notReached(target: .orientation(.portrait), last: .orientation(.faceUp)))
    }
  }

  func testReachedPoseWithUnsettledDisplaysReturnsTheTransitioningConfiguration() async throws {
    let poses = OrientationPoseDouble([.success(.portrait)], displays: [.displays([display]), .transitioning(incoming: nil)])
    _ = try await poses.displays.settledConfiguration(within: .zero)
    let configuration = try await poses.set(.portrait, confirmingWithin: .milliseconds(20), interval: .milliseconds(1))
    XCTAssertEqual(configuration, SimulatorDisplayConfiguration(generation: 1, displays: [display], active: .identified(display), phase: .transitioning(incoming: nil)))
  }

  func testFailedReadIsThrown() async {
    let poses = OrientationPoseDouble([.failure(SimulatorCoreDeviceError.timedOut)], displays: [.displays([display])])
    do {
      _ = try await poses.set(.portrait, confirmingWithin: .seconds(1), interval: .milliseconds(1))
      XCTFail("Expected the read's failure")
    } catch {
      XCTAssertEqual(error as? SimulatorCoreDeviceError, .timedOut)
    }
  }

  func testNotReachedDescribesBothPoses() throws {
    let error = SimulatorPoseConfirmationError.notReached(
      target: .hinge(try SimulatorHingeAngle(degrees: 90)), last: .hinge(try SimulatorHingeAngle(degrees: 45)))
    XCTAssertEqual(error.errorDescription, "Simulator did not reach hinge at 90.0 degrees; last read hinge at 45.0 degrees")
  }
}
