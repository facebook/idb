/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// Commands that own something outliving a single call — a notifier, an in-flight video, a task —
// are memoized through `commandCache` (`TargetCommandCache`), whose lock also stops two callers
// racing the first construction. Commands that only wrap the simulator are built per call: a slot
// for one would hold a box around a pointer back to the object owning the cache, closing a retain
// cycle.
extension FBSimulator {

  // MARK: - Shared accessors

  public var application: SimulatorApplicationCommands {
    SimulatorApplicationCommands.commands(with: self)
  }

  public var crashLog: SimulatorCrashLogCommands {
    commandCache.resolve { SimulatorCrashLogCommands.commands(with: self) }
  }

  public var screenshot: SimulatorScreenshotCommands {
    commandCache.resolve { SimulatorScreenshotCommands.commands(with: self) }
  }

  public var location: SimulatorLocationCommands {
    SimulatorLocationCommands.commands(with: self)
  }

  public var debugger: SimulatorDebuggerCommands {
    commandCache.resolve { SimulatorDebuggerCommands.commands(with: self) }
  }

  public var file: SimulatorFileCommands {
    SimulatorFileCommands.commands(with: self)
  }

  public var log: SimulatorLogCommands {
    SimulatorLogCommands.commands(with: self)
  }

  public var processSpawn: SimulatorProcessSpawnCommands {
    SimulatorProcessSpawnCommands.commands(with: self)
  }

  public var videoRecording: SimulatorVideoRecordingCommands {
    commandCache.resolve { SimulatorVideoRecordingCommands.commands(with: self) }
  }

  public var videoStream: SimulatorVideoStreamCommands {
    SimulatorVideoStreamCommands.commands(with: self)
  }

  public var launchCtl: SimulatorLaunchCtlCommands {
    SimulatorLaunchCtlCommands.commands(with: self)
  }

  public var xctraceRecord: FBXCTraceRecordCommands {
    FBXCTraceRecordCommands.commands(with: self)
  }

  public var instruments: SimulatorInstrumentsCommands {
    SimulatorInstrumentsCommands.commands(with: self)
  }

  // MARK: - Sim-only accessors

  public var lifecycle: SimulatorLifecycleCommands {
    commandCache.resolve { SimulatorLifecycleCommands.commands(with: self) }
  }

  public var power: SimulatorPowerCommands {
    SimulatorPowerCommands.commands(with: self)
  }

  public var erase: SimulatorEraseCommands {
    SimulatorEraseCommands.commands(with: self)
  }

  public var media: SimulatorMediaCommands {
    SimulatorMediaCommands.commands(with: self)
  }

  public var keychain: SimulatorKeychainCommands {
    SimulatorKeychainCommands.commands(with: self)
  }

  public var privacy: SimulatorPrivacyCommands {
    SimulatorPrivacyCommands.commands(with: self)
  }

  public var preferences: SimulatorPreferencesCommands {
    SimulatorPreferencesCommands.commands(with: self)
  }

  public var statusBar: SimulatorStatusBarCommands {
    SimulatorStatusBarCommands.commands(with: self)
  }

  public var network: SimulatorNetworkCommands {
    SimulatorNetworkCommands.commands(with: self)
  }

  public var health: SimulatorHealthCommands {
    SimulatorHealthCommands.commands(with: self)
  }

  public var contacts: SimulatorContactsCommands {
    SimulatorContactsCommands.commands(with: self)
  }

  public var photos: SimulatorPhotosCommands {
    SimulatorPhotosCommands.commands(with: self)
  }

  /// The converged UI-automation surface for `backend` — element reads and element-targeted actions
  /// over a single query-shaped API. Every call returns a fresh reader; the readers are cheap, and
  /// where a backend owns an expensive warm resource, who owns it differs by backend:
  ///
  /// - `.axBridge(persistence: .shared, …)` reads over a guest `serve` process on the simulator's
  ///   well-known socket, shared with every other process reading the same simulator. The connection is
  ///   released after each round trip so the next reader can have it, and no host ever ends the guest —
  ///   only its own idle timeout does.
  /// - `.axBridge(persistence: .exclusive, …)` reads over a guest of the caller's own, on a socket
  ///   nobody else can discover. Memoized per simulator and per persistence, and holds its connection
  ///   between reads. The guest was spawned with `--exit-on-disconnect`, so closing that connection is
  ///   what ends it — for a process that owns the simulator for its lifetime.
  /// - `.accessibility` and `.axBridge(persistence: .oneShot, …)` are stateless — they hold no warm
  ///   resource, so reconstructing them per call is free.
  public func uiAutomation(backend: FBUIAutomationBackend) throws -> any FBUIAutomation {
    switch backend {
    case .accessibility:
      return AccessibilityUIAutomation(simulator: self)
    case let .axBridge(persistence, frontmostMethod, automationMode):
      let transport: any AXBridgeTransport =
        switch persistence {
        case .oneShot: AXBridgeOneshotTransport(simulator: self)
        case .shared: axBridgeTransport(scope: .shared)
        case .exclusive: axBridgeTransport(scope: .exclusive)
        }
      return AXBridgeUIAutomation(
        simulator: self, transport: transport, persistence: persistence, frontmostMethod: frontmostMethod,
        automationMode: automationMode
      )
    }
  }

  var accessibility: SimulatorAccessibilityCommands {
    commandCache.resolve { SimulatorAccessibilityCommands.commands(with: self) }
  }

  public var dapServer: SimulatorDapServerCommand {
    SimulatorDapServerCommand.commands(with: self)
  }

  public var notification: SimulatorNotificationCommands {
    SimulatorNotificationCommands.commands(with: self)
  }

  public var memory: SimulatorMemoryCommands {
    SimulatorMemoryCommands.commands(with: self)
  }

  public var audio: SimulatorAudioCommands {
    SimulatorAudioCommands.commands(with: self)
  }

  public var runtimeTools: SimulatorRuntimeToolCommands {
    SimulatorRuntimeToolCommands.commands(with: self)
  }

  public var bootstrapPorts: SimulatorBootstrapPortCommands {
    SimulatorBootstrapPortCommands.commands(with: self)
  }
}
