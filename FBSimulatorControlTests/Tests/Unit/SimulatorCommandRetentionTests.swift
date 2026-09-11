/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Foundation
import SimulatorXCTest
import Testing

/// Every command accessor on `FBSimulator`, so the retention rule is checked against all of them
/// rather than a hand-picked few.
enum SimulatorCommandAccessor: CaseIterable, Sendable {
  case application
  case crashLog
  case screenshot
  case location
  case debugger
  case file
  case log
  case processSpawn
  case videoRecording
  case videoStream
  case launchCtl
  case xctraceRecord
  case instruments
  case lifecycle
  case power
  case erase
  case media
  case keychain
  case privacy
  case preferences
  case statusBar
  case network
  case health
  case contacts
  case photos
  case xctest
  case uiAutomation
  case accessibility
  case dapServer
  case repl
  case notification
  case memory
  case audio
  case runtimeTools
  case bootstrapPorts

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
    case .videoStream:
      _ = simulator.videoStream
    case .launchCtl:
      _ = simulator.launchCtl
    case .xctraceRecord:
      _ = simulator.xctraceRecord
    case .instruments:
      _ = simulator.instruments
    case .lifecycle:
      _ = simulator.lifecycle
    case .power:
      _ = simulator.power
    case .erase:
      _ = simulator.erase
    case .media:
      _ = simulator.media
    case .keychain:
      _ = simulator.keychain
    case .privacy:
      _ = simulator.privacy
    case .preferences:
      _ = simulator.preferences
    case .statusBar:
      _ = simulator.statusBar
    case .network:
      _ = simulator.network
    case .health:
      _ = simulator.health
    case .contacts:
      _ = simulator.contacts
    case .photos:
      _ = simulator.photos
    case .xctest:
      _ = simulator.xctest
    case .uiAutomation:
      // Every backend, since only the persistent axbridge scopes resolve a transport into the cache.
      for name in FBUIAutomationBackendName.allCases {
        _ = try? simulator.uiAutomation(backend: FBUIAutomationBackend(resolvedName: name))
      }
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
    case .audio:
      _ = simulator.audio
    case .runtimeTools:
      _ = simulator.runtimeTools
    case .bootstrapPorts:
      _ = simulator.bootstrapPorts
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
struct SimulatorCommandRetentionTests {

  /// Resolves a command, then reports whether the simulator survived the only strong reference to
  /// it going away.
  private func simulatorSurvives(_ resolve: (FBSimulator) -> Void) -> Bool {
    weak var weakSimulator: FBSimulator?
    autoreleasepool {
      let simulator = SimulatorTestSupport.testableSimulator()
      weakSimulator = simulator
      resolve(simulator)
    }
    return weakSimulator != nil
  }

  @Test("Resolving a command does not retain the simulator", arguments: SimulatorCommandAccessor.allCases)
  func resolvingACommandDoesNotRetainTheSimulator(_ accessor: SimulatorCommandAccessor) {
    #expect(simulatorSurvives { accessor.resolve(on: $0) } == false)
  }
}
