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

  /// The interaction target of the latest report in `event`, or nil when there is none or it cannot
  /// select a display, as mid-transition. An event on another side channel is malformed.
  static func target(_ event: xpc_object_t, channel: UUID) throws -> SimulatorDisplayTarget? {
    let event = try SimulatorCoreDevice.decode(StreamEvent.self, from: event)
    guard event.channel == channel.uuidString else { throw SimulatorCoreDeviceError.malformed("Unexpected side channel") }
    guard let report = event.status.pushing.elements.last,
      case let .target(target) = SimulatorDisplayResolution(SimulatorDisplayProtocol.report(of: report))
    else { return nil }
    return target
  }
}
