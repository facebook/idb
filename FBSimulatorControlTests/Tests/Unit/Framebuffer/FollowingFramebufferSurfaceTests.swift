/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import IOSurface
import XCTest

final class FollowingFramebufferSurfaceTests: XCTestCase {

  private struct LocateFailure: Error {}

  private func display(_ id: String) -> SimulatorDisplay {
    SimulatorDisplay(
      uniqueID: id, name: id, activity: .active, isPrimary: false, isIntegrated: true,
      bounds: CGRect(x: 0, y: 0, width: 1200, height: 800), scale: 2, rotation: .upright)
  }

  private func surface(_ screens: [String: FakeFramebufferSurface], updates: AsyncStream<SimulatorDisplay>, failing: Set<String> = []) -> FollowingFramebufferSurface {
    let locations = LockedCount()
    return FollowingFramebufferSurface(
      displayUniqueID: "cover", surface: screens["cover"]!,
      updates: { updates },
      locate: { [screens] uniqueID in
        locations.increment()
        guard !failing.contains(uniqueID) || locations.value > 1, let screen = screens[uniqueID] else { throw LocateFailure() }
        return screen
      },
      logger: CapturingLogger())
  }

  private func waitUntil(_ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
    let deadline = Date(timeIntervalSinceNow: 5)
    while !condition() {
      guard deadline.timeIntervalSinceNow > 0 else { return XCTFail("condition never held", file: file, line: line) }
      try await Task.sleep(for: .milliseconds(1))
    }
  }

  func testMovingToAnotherDisplayReRegistersOnItsScreenAndReportsItsSurface() async throws {
    let cover = FakeFramebufferSurface()
    let inner = FakeFramebufferSurface()
    inner.immediateSurface = makeTestIOSurface(width: 20, height: 30)
    let (updates, continuation) = AsyncStream.makeStream(of: SimulatorDisplay.self)
    let following = surface(["cover": cover, "inner": inner], updates: updates)
    let token = UUID()
    var reported: [IOSurface?] = []
    try following.registerCallbacks(token: token, ioSurfaceChanged: { reported.append($0) }, frameRendered: {})

    continuation.yield(display("inner"))
    try await waitUntil { !inner.registeredTokens.isEmpty }

    XCTAssertEqual(inner.registeredTokens, [token])
    XCTAssertEqual(cover.unregisteredTokens, [token])
    XCTAssertEqual(reported.map { $0.map(IOSurfaceGetID) }, [inner.immediateSurface.map(IOSurfaceGetID)])
    XCTAssertTrue(following.immediatelyAvailableSurface() === inner.immediateSurface)
  }

  func testAConsumerCanUseTheSurfaceWhenToldOfAMove() async throws {
    let cover = FakeFramebufferSurface()
    let inner = FakeFramebufferSurface()
    inner.immediateSurface = makeTestIOSurface(width: 20, height: 30)
    let (updates, continuation) = AsyncStream.makeStream(of: SimulatorDisplay.self)
    let following = surface(["cover": cover, "inner": inner], updates: updates)
    let token = UUID()
    let seen = LockedCount()
    try following.registerCallbacks(
      token: token,
      ioSurfaceChanged: { _ in
        _ = following.immediatelyAvailableSurface()
        following.unregisterCallbacks(token: token)
        seen.increment()
      },
      frameRendered: {})

    continuation.yield(display("inner"))
    try await waitUntil { seen.value == 1 }

    XCTAssertEqual(inner.unregisteredTokens, [token])
  }

  func testTheLeftScreenNoLongerReachesConsumers() async throws {
    let cover = FakeFramebufferSurface()
    let inner = FakeFramebufferSurface()
    let (updates, continuation) = AsyncStream.makeStream(of: SimulatorDisplay.self)
    let following = surface(["cover": cover, "inner": inner], updates: updates)
    var frames = 0
    var surfaces = 0
    try following.registerCallbacks(token: UUID(), ioSurfaceChanged: { _ in surfaces += 1 }, frameRendered: { frames += 1 })
    let coverFrame = try XCTUnwrap(cover.frameRendered)
    let coverSurface = try XCTUnwrap(cover.ioSurfaceChanged)

    continuation.yield(display("inner"))
    try await waitUntil { !inner.registeredTokens.isEmpty }
    coverFrame()
    coverSurface(makeTestIOSurface())
    inner.frameRendered?()

    XCTAssertEqual(frames, 1)
    XCTAssertEqual(surfaces, 1)
  }

  func testTheFollowedDisplayReportedAgainKeepsItsScreen() async throws {
    let cover = FakeFramebufferSurface()
    let inner = FakeFramebufferSurface()
    let (updates, continuation) = AsyncStream.makeStream(of: SimulatorDisplay.self)
    let following = surface(["cover": cover, "inner": inner], updates: updates)
    try following.registerCallbacks(token: UUID(), ioSurfaceChanged: { _ in }, frameRendered: {})

    continuation.yield(display("cover"))
    continuation.yield(display("inner"))
    try await waitUntil { !inner.registeredTokens.isEmpty }

    XCTAssertEqual(cover.registeredTokens.count, 1)
    XCTAssertEqual(cover.unregisteredTokens.count, 1)
  }

  func testADisplayThatCannotBeCapturedLeavesTheCurrentOneUntilALaterUpdate() async throws {
    let cover = FakeFramebufferSurface()
    let inner = FakeFramebufferSurface()
    let (updates, continuation) = AsyncStream.makeStream(of: SimulatorDisplay.self)
    let following = surface(["cover": cover, "inner": inner], updates: updates, failing: ["inner"])
    try following.registerCallbacks(token: UUID(), ioSurfaceChanged: { _ in }, frameRendered: {})

    continuation.yield(display("inner"))
    continuation.yield(display("inner"))
    try await waitUntil { !inner.registeredTokens.isEmpty }

    XCTAssertEqual(inner.registeredTokens.count, 1)
    XCTAssertEqual(cover.unregisteredTokens.count, 1)
  }

  func testRemovingTheLastConsumerStopsFollowing() async throws {
    let cover = FakeFramebufferSurface()
    let (updates, continuation) = AsyncStream.makeStream(of: SimulatorDisplay.self)
    let stopped = LockedCount()
    continuation.onTermination = { _ in stopped.increment() }
    let following = surface(["cover": cover], updates: updates)
    let first = UUID()
    let second = UUID()
    try following.registerCallbacks(token: first, ioSurfaceChanged: { _ in }, frameRendered: {})
    try following.registerCallbacks(token: second, ioSurfaceChanged: { _ in }, frameRendered: {})

    following.unregisterCallbacks(token: first)
    try await Task.sleep(for: .milliseconds(20))
    XCTAssertEqual(stopped.value, 0)

    following.unregisterCallbacks(token: second)
    try await waitUntil { stopped.value == 1 }
    XCTAssertEqual(cover.unregisteredTokens, [first, second])
  }

  func testUpdatesReportEachSelectedDisplayAndSkipFailedReadsAndASoleDisplay() async throws {
    let displays = DisplayCommandsDouble([
      .success(.reporting(.selected(display("cover")))), .success(.transitioning),
      .success(.reporting(.sole(.identified(display("lcd"))))), .success(.reporting(.selected(display("inner")))),
    ])
    var reported: [String] = []
    for await update in displays.polledActiveDisplayUpdates(interval: .milliseconds(1)) {
      reported.append(update.uniqueID)
      if reported.count == 3 { break }
    }

    XCTAssertEqual(reported, ["cover", "inner", "inner"])
  }
}

private final class LockedCount: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var value: Int { lock.withLock { count } }

  func increment() { lock.withLock { count += 1 } }
}
