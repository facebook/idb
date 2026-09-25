/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XPC

/// The `displayinfo` feature: what the provider reports about each display, and what a current
/// report has to say before a display can be selected from it.
enum SimulatorDisplayProtocol {
  static let service = "com.apple.coredevice.feature.getdisplayinfo"
  static let action = "com.apple.coredevice.action.displayinfo"

  /// The output as the provider sends it. Activity and stable identity are optional only because
  /// older providers omit both from every display; see `snapshot`.
  struct Report: Decodable {
    struct Record: Decodable {
      let uniqueId: String?
      let name: String
      let active: Bool?
      let backlightState: String?
      let primary: Bool
      let bounds: [[Double]]
      let pointScale: Int64
      let currentOrientation: SimulatorDisplayRotation
      let type: [String: XPCValue]
    }

    let current: Bool
    let displays: [Record]
  }

  /// Whether a report can select a display, or comes from a provider that cannot say which is active.
  enum Snapshot: Equatable {
    case displays([SimulatorDisplay])
    case legacyProvider
  }

  private static let maximumDisplays = 32
  private static let maximumStringLength = 1024

  /// A report with identity and activity yields displays; one that omits both from every display
  /// is a legacy provider. A report that has them on some displays but not others is malformed.
  static func snapshot(_ reply: xpc_object_t) throws -> Snapshot {
    try snapshot(of: validated(CoreDeviceReply.decode(Report.self, from: reply)))
  }

  /// A legacy provider can still be used for interaction when it reports exactly one integrated display.
  static func interactionDisplay(_ reply: xpc_object_t) throws -> SimulatorInteractionDisplay {
    let report = try validated(CoreDeviceReply.decode(Report.self, from: reply))
    if case let .displays(displays) = try snapshot(of: report) {
      return .identified(try SimulatorDisplayCommands.activeIntegratedDisplay(in: displays))
    }
    var integrated: [SimulatorDisplayGeometry] = []
    for record in report.displays {
      let validated = try validated(record)
      guard validated.integrated else { continue }
      guard !validated.bounds.isEmpty else { throw SimulatorCoreDeviceError.malformed("Invalid integrated display geometry") }
      integrated.append(
        SimulatorDisplayGeometry(bounds: validated.bounds, scale: Double(record.pointScale), rotation: record.currentOrientation))
    }
    guard integrated.count == 1, let geometry = integrated.first else {
      throw SimulatorDisplayInteractionError.unsupportedCapability("unambiguous legacy integrated display selection")
    }
    return .legacy(geometry)
  }

  private static func snapshot(of report: Report) throws -> Snapshot {
    let legacy = report.displays.allSatisfy { $0.active == nil && $0.uniqueId == nil }
    guard legacy, !report.displays.isEmpty else {
      return .displays(try displays(in: report))
    }
    for record in report.displays {
      _ = try validated(record)
    }
    return .legacyProvider
  }

  /// A current report with explicit per-display activity and identity.
  static func displays(_ reply: xpc_object_t) throws -> [SimulatorDisplay] {
    try displays(in: validated(CoreDeviceReply.decode(Report.self, from: reply)))
  }

  private static func validated(_ report: Report) throws -> Report {
    guard report.current else { throw SimulatorCoreDeviceError.malformed("Report is not current") }
    guard report.displays.count <= maximumDisplays else { throw SimulatorCoreDeviceError.malformed("Too many displays") }
    return report
  }

  private static func displays(in report: Report) throws -> [SimulatorDisplay] {
    let hasLayoutActivity = report.displays.contains { $0.active != nil }
    var identifiers: Set<String> = []
    var displays: [SimulatorDisplay] = []
    for record in report.displays {
      let validated = try validated(record)
      guard let id = record.uniqueId, !id.isEmpty, id.utf8.count <= maximumStringLength, identifiers.insert(id).inserted else {
        throw SimulatorCoreDeviceError.malformed("Duplicate or empty display identity")
      }
      let active = try activity(of: record, integrated: validated.integrated, hasLayoutActivity: hasLayoutActivity)
      guard !active || !validated.bounds.isEmpty else { throw SimulatorCoreDeviceError.malformed("Active display has empty bounds") }
      displays.append(
        SimulatorDisplay(
          uniqueID: id, name: record.name, isActive: active, isPrimary: record.primary, isIntegrated: validated.integrated,
          bounds: validated.bounds, scale: Double(record.pointScale), rotation: record.currentOrientation,
          activitySource: hasLayoutActivity ? .layout : .backlight))
    }
    return displays.sorted { $0.uniqueID < $1.uniqueID }
  }

  /// Layout activity is authoritative when the report carries it; otherwise backlight state identifies
  /// the illuminated display.
  private static func activity(of record: Report.Record, integrated: Bool, hasLayoutActivity: Bool) throws -> Bool {
    if hasLayoutActivity {
      guard let active = record.active else { throw SimulatorCoreDeviceError.malformed("Display has no activity") }
      if !active, let state = record.backlightState, ["activeOn", "activeDimmed"].contains(state) {
        throw SimulatorCoreDeviceError.malformed("Layout and backlight activity disagree")
      }
      return active
    }
    switch record.backlightState {
    case "activeOn", "activeDimmed": return true
    case "off", "inactiveOn": return false
    case "unknown":
      guard !integrated else { throw SimulatorDisplayInteractionError.unsupportedCapability("integrated display activity") }
      return false
    case nil: throw SimulatorCoreDeviceError.malformed("Display has no activity")
    default: throw SimulatorCoreDeviceError.malformed("Unknown backlight state")
    }
  }

  /// The fields every record has to satisfy, legacy or not.
  private static func validated(_ record: Report.Record) throws -> (bounds: CGRect, integrated: Bool) {
    guard record.name.utf8.count <= maximumStringLength else { throw SimulatorCoreDeviceError.malformed("name") }
    guard record.pointScale > 0 else { throw SimulatorCoreDeviceError.malformed("Invalid display scale") }
    guard record.type.count == 1 else { throw SimulatorCoreDeviceError.malformed("Invalid display type") }
    return (try rectangle(record.bounds), record.type["integrated"] != nil)
  }

  /// Bounds arrive as `[[x, y], [width, height]]`.
  private static func rectangle(_ value: [[Double]]) throws -> CGRect {
    guard value.count == 2, value[0].count == 2, value[1].count == 2 else {
      throw SimulatorCoreDeviceError.malformed("Invalid bounds")
    }
    let (x, y, width, height) = (value[0][0], value[0][1], value[1][0], value[1][1])
    guard [x, y, width, height].allSatisfy(\.isFinite) else { throw SimulatorCoreDeviceError.malformed("Non-finite coordinate") }
    guard width >= 0, height >= 0 else { throw SimulatorCoreDeviceError.malformed("Negative size") }
    return CGRect(x: x, y: y, width: width, height: height)
  }
}
