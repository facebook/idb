/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

enum NetworkConfigurationAction: String {
  case list
  case set
  case clear
}

enum NotificationSettingsAction: String {
  case check
  case list
  case approve
  case revoke
}
