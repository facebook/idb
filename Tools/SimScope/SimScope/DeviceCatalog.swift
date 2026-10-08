/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import FBControlCore
import FBSimulatorControl
import Foundation

/// Which device set a simulator lives in. CoreSimulator has no way to enumerate sets — a set is just
/// a directory — so beyond the standard one, SimScope only knows the sets it has been shown.
enum DeviceSetIdentity: Hashable {
  case standard
  case custom(path: String)

  /// Where the standard set lives, for recognising it when someone picks it in the chooser.
  static var standardPath: String {
    NSHomeDirectory() + "/Library/Developer/CoreSimulator/Devices"
  }
}

/// Where windows come from: the simulators SimScope can see, listed and resolved through one
/// `SimulatorControlBootstrap` handle per device set rather than one per connection.
///
/// Constructing a handle loads the private CoreSimulator frameworks and opens its device set; both
/// are expensive and the frameworks are process-wide, so handles are made once and kept.
@MainActor
final class DeviceCatalog {

  static let shared = DeviceCatalog()

  /// One simulator, as a value — so a menu can hold the list without holding CoreSimulator objects
  /// whose state has moved on by the time the menu is read.
  struct Device {
    let udid: String
    let name: String
    let state: String
    let isBooted: Bool
  }

  /// One device set as the picker shows it. An unavailable set keeps its row rather than vanishing:
  /// a set disappearing out from under its windows is worth seeing, not silently forgetting.
  struct SetListing {
    let identity: DeviceSetIdentity
    let label: String
    let available: Bool
    let devices: [Device]
  }

  private var controls: [DeviceSetIdentity: SimulatorControlBootstrap] = [:]

  private func control(for identity: DeviceSetIdentity) throws -> SimulatorControlBootstrap {
    if let held = controls[identity] { return held }
    // Passing nil logger/reporter uses ControlCoreGlobalConfiguration.defaultLogger and loads the
    // private CoreSimulator frameworks as a side effect of constructing the configuration.
    let path: String?
    switch identity {
    case .standard: path = nil
    case let .custom(custom): path = custom
    }
    let configuration = SimulatorControlConfiguration(deviceSetPath: path, logger: nil)
    let created = try SimulatorControlBootstrap.withConfiguration(configuration)
    controls[identity] = created
    return created
  }

  // MARK: - Chosen sets

  private static let chosenSetsKey = "SimScopeChosenDeviceSets"

  /// The custom set paths this Mac's SimScope has been shown, in the order they were chosen.
  private var chosenSetPaths: [String] {
    UserDefaults.standard.stringArray(forKey: Self.chosenSetsKey) ?? []
  }

  /// Remembers a chosen set across launches. Picking the standard set's own directory is a no-op —
  /// it is always listed — as is picking a set twice.
  func remember(path: String) {
    let resolved = (path as NSString).standardizingPath
    guard resolved != DeviceSetIdentity.standardPath else { return }
    var paths = chosenSetPaths
    guard !paths.contains(resolved) else { return }
    paths.append(resolved)
    UserDefaults.standard.set(paths, forKey: Self.chosenSetsKey)
  }

  func forget(path: String) {
    UserDefaults.standard.set(chosenSetPaths.filter { $0 != path }, forKey: Self.chosenSetsKey)
    controls[.custom(path: path)] = nil
  }

  /// Every set the catalog knows: the standard one first, then each chosen set in chosen order.
  func listings() -> [SetListing] {
    var listings = [listing(for: .standard, label: "Default Device Set")]
    for path in chosenSetPaths {
      let label = (path as NSString).abbreviatingWithTildeInPath
      listings.append(listing(for: .custom(path: path), label: label))
    }
    return listings
  }

  private func listing(for identity: DeviceSetIdentity, label: String) -> SetListing {
    if case let .custom(path) = identity, !FileManager.default.fileExists(atPath: path) {
      return SetListing(identity: identity, label: label, available: false, devices: [])
    }
    do {
      return SetListing(identity: identity, label: label, available: true, devices: try devices(in: identity))
    } catch {
      return SetListing(identity: identity, label: label, available: false, devices: [])
    }
  }

  /// Every simulator in one set, booted ones first and each group by name — the order a picker
  /// wants, because the booted handful is what an operator is almost always after.
  private func devices(in identity: DeviceSetIdentity) throws -> [Device] {
    try control(for: identity).set.allSimulators
      .map {
        Device(
          udid: $0.udid, name: $0.name, state: Self.word(for: $0.state),
          isBooted: $0.state == .booted)
      }
      .sorted { ($0.isBooted ? 0 : 1, $0.name) < ($1.isBooted ? 0 : 1, $1.name) }
  }

  /// The state as a lower-case word for a menu row; the canonical `TargetStateString` is title-cased.
  private static func word(for state: TargetState) -> String {
    switch state {
    case .creating: return "creating"
    case .shutdown: return "shutdown"
    case .booting: return "booting"
    case .booted: return "booted"
    case .shuttingDown: return "shutting down"
    case .DFU: return "dfu"
    case .recovery: return "recovery"
    case .restoreOS: return "restoring"
    default: return "unknown"
    }
  }

  // MARK: - Thumbnails

  /// The named simulator in whichever known set holds it, without any state requirement.
  private func simulator(withUDID udid: String) -> Simulator? {
    var identities: [DeviceSetIdentity] = [.standard]
    identities.append(contentsOf: chosenSetPaths.map { .custom(path: $0) })
    for identity in identities {
      if let match = (try? control(for: identity))?.set.simulator(withUDID: udid) { return match }
    }
    return nil
  }

  /// What a booted simulator is displaying right now, as one still — nil for anything not booted,
  /// which has no framebuffer to read.
  ///
  /// `SimulatorImage` is an actor that attaches its own framebuffer on first use and detaches when
  /// released, so a thumbnail costs an attachment only for as long as the fetch takes. Callers with a
  /// window on the device should use that window's surface instead of attaching a second time.
  func thumbnailImage(udid: String) async -> CGImage? {
    guard let simulator = simulator(withUDID: udid), simulator.state == .booted else { return nil }
    guard
      let framebuffer = try? Framebuffer.mainScreenSurface(
        for: simulator, logger: ControlCoreGlobalConfiguration.defaultLogger)
    else { return nil }
    let image = SimulatorImage.image(with: framebuffer, logger: nil)
    return try? await image.image()
  }

  // MARK: - Connecting

  /// A backend for the named booted simulator — or, with no name, the first booted one found.
  /// Resolution scans the standard set first and then each chosen set, so a UDID from any known set
  /// works wherever a UDID is accepted, `--udid` included.
  func connectBooted(udid: String?) throws -> SimBackend {
    var identities: [DeviceSetIdentity] = [.standard]
    identities.append(contentsOf: chosenSetPaths.map { .custom(path: $0) })

    var matched: Simulator?
    for identity in identities {
      guard let set = try? control(for: identity).set else { continue }
      if let udid {
        if let match = set.simulator(withUDID: udid) {
          guard match.state == .booted else {
            throw SimScopeError.notBooted(udid: udid, state: Self.word(for: match.state))
          }
          matched = match
          break
        }
      } else if let booted = set.allSimulators.first(where: { $0.state == .booted }) {
        matched = booted
        break
      }
    }
    guard let simulator = matched else {
      if let udid { throw SimScopeError.udidNotFound(udid) }
      throw SimScopeError.noBootedSimulator
    }
    return try SimBackend(simulator: simulator, logger: ControlCoreGlobalConfiguration.defaultLogger)
  }
}
