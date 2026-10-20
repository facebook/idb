/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The guest's answer to an accessibility request: what the request's verb answers with, or why it could not. It
/// travels as its case keyed to what it holds: `{"tree":{"response":{…}}}`, `{"failure":{"reason":{…}}}`.
@frozen public enum BridgeAXAnswer: Codable, Equatable, Sendable {
  case tree(BridgeAXTreeResponse)
  case hitTest(BridgeAXHitTestResponse)
  case write(BridgeAXWriteResponse)
  case setting(BridgeAXSettingResponse)
  case displays(BridgeAXDisplayInventory)
  case settingSnapshot(BridgeAXSettingSnapshot)
  case quiescence(BridgeAXQuiescenceEvent)
  /// Why the request could not be answered, which reads the same whatever it asked.
  case failure(BridgeAXFailure)

  // Swift names an unlabelled payload `_0`; these name it for what it holds.
  private enum TreeCodingKeys: String, CodingKey { case _0 = "response" }
  private enum HitTestCodingKeys: String, CodingKey { case _0 = "response" }
  private enum WriteCodingKeys: String, CodingKey { case _0 = "response" }
  private enum SettingCodingKeys: String, CodingKey { case _0 = "response" }
  private enum DisplaysCodingKeys: String, CodingKey { case _0 = "inventory" }
  private enum SettingSnapshotCodingKeys: String, CodingKey { case _0 = "snapshot" }
  private enum QuiescenceCodingKeys: String, CodingKey { case _0 = "event" }
  private enum FailureCodingKeys: String, CodingKey { case _0 = "reason" }

  public var succeeded: Bool {
    guard case .failure = self else { return true }
    return false
  }
}
