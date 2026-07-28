/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A privacy/permission service whose access can be granted or revoked on a target.
/// Raw values are the wire/CLI names (e.g. `contacts`, `url`, `notification`).
public enum FBTargetSettingsService: String, CaseIterable, Codable, Sendable {
  case contacts
  case photos
  case camera
  case location
  case microphone
  case url
  case notification
  case health
}
