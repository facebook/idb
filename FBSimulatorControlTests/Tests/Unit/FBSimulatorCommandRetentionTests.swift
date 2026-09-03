/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import Testing

/// Every command accessor on `FBSimulator`, so the retention rule is checked against all of them
/// rather than a hand-picked few.
enum FBSimulatorCommandAccessor: CaseIterable, Sendable {
  case application
  case crashLog
  case screenshot
  case location
  case debugger
  case file
  case log
  case processSpawn
  case videoRecording
  case launchCtl
  case xctraceRecord
  case lifecycle
  case media
  case keychain
  case settings
  case xctestExtended
  case accessibility
  case dapServer
  case repl
  case notification
  case memory

  func resolve(on simulator: FBSimulator) {
    switch self {
    case .application:
      _ = simulator.application
    case .crashLog:
      _ = simulator.crashLog
    case .screenshot:
      _ = simulator.screenshot
    case .location:
      _ = simulator.location
    case .debugger:
      _ = simulator.debugger
    case .file:
      _ = simulator.file
    case .log:
      _ = simulator.log
    case .processSpawn:
      _ = simulator.processSpawn
    case .videoRecording:
      _ = simulator.videoRecording
    case .launchCtl:
      _ = simulator.launchCtl
    case .xctraceRecord:
      _ = simulator.xctraceRecord
    case .lifecycle:
      _ = simulator.lifecycle
    case .media:
      _ = simulator.media
    case .keychain:
      _ = simulator.keychain
    case .settings:
      _ = simulator.settings
    case .xctestExtended:
      _ = simulator.xctestExtended
    case .accessibility:
      _ = simulator.accessibility
    case .dapServer:
      _ = simulator.dapServer
    case .repl:
      _ = simulator.repl
    case .notification:
      _ = simulator.notification
    case .memory:
      _ = simulator.memory
    }
  }
}

/// Whether resolving a command class keeps the simulator alive.
///
/// A simulator owns its `commandCache`; the cache owns whatever is resolved into it. A memoized
/// command that holds its simulator strongly therefore closes a cycle — simulator to cache to
/// command to simulator — and the simulator can never be released, which is why the memoized
/// commands hold `weak var simulator`. Commands built per call are free to hold it strongly:
/// nothing outlives the call that builds them.
///
/// Asserting over every accessor rather than the memoized ones keeps the rule intact when a
/// per-call command is later moved into the cache.
@Suite("Simulator command retention")
struct FBSimulatorCommandRetentionTests {

  /// Resolves a command, then reports whether the simulator survived the only strong reference to
  /// it going away.
  private func simulatorSurvives(_ resolve: (FBSimulator) -> Void) -> Bool {
    weak var weakSimulator: FBSimulator?
    autoreleasepool {
      let simulator = FBSimulatorTestSupport.testableSimulator()
      weakSimulator = simulator
      resolve(simulator)
    }
    return weakSimulator != nil
  }

  @Test("Resolving a command does not retain the simulator", arguments: FBSimulatorCommandAccessor.allCases)
  func resolvingACommandDoesNotRetainTheSimulator(_ accessor: FBSimulatorCommandAccessor) {
    #expect(simulatorSurvives { accessor.resolve(on: $0) } == false)
  }
}
