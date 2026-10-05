/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XPC

/// The `displayinfoupdates` feature: a stream that pushes a full `displayinfo` report whenever a
/// display changes, starting with the current one.
enum SimulatorDisplayUpdatesProtocol {
  static let service = "com.apple.coredevice.feature.displayinfoupdates"
  static let action = "com.apple.coredevice.action.displayinfoupdates"

  struct StreamInput: Encodable {
    struct StreamProxy: Encodable {
      let sideChannel: UUID
    }
    let actualInput = CoreDeviceEmptyInput()
    let streamProxy: StreamProxy

    init(channel: UUID) {
      streamProxy = StreamProxy(sideChannel: channel)
    }
  }

  struct StreamEvent: Decodable {
    struct Pushing: Decodable {
      let elements: [SimulatorDisplayProtocol.Report]
    }
    struct Status: Decodable {
      let pushing: Pushing
    }

    let channel: String
    let status: Status

    private enum CodingKeys: String, CodingKey {
      case channel = "XPCSideChannel.uniqueIdentifier"
      case status = "CoreDevice.XPCMessageKey.sideChannelStatus"
    }
  }

  /// The latest report in `event`, or nil when it carries none. An event on another side channel is malformed.
  static func report(_ event: xpc_object_t, channel: UUID) throws -> SimulatorDisplayReport? {
    let event = try SimulatorCoreDevice.decode(StreamEvent.self, from: event)
    guard event.channel == channel.uuidString else { throw SimulatorCoreDeviceError.malformed("Unexpected side channel") }
    return event.status.pushing.elements.last.map(SimulatorDisplayProtocol.report(of:))
  }

  /// The interaction target of the latest report in `event`, or nil when there is none or it cannot
  /// select a display, as mid-transition.
  static func target(_ event: xpc_object_t, channel: UUID) throws -> SimulatorDisplayTarget? {
    guard let report = try report(event, channel: channel), case let .target(target) = SimulatorDisplayResolution(report) else {
      return nil
    }
    return target
  }
}
