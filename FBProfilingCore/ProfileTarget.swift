/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// The process a profiler inspects.
public enum ProfileTarget: Equatable, Sendable {
  case pid(pid_t)
  /// The running process of an installed application.
  case bundleID(String)
  /// An installed application, launched by the profiler so the profile covers its startup. Only `trace` supports it.
  case launch(bundleID: String)
  /// Every process on the target. Only `trace` supports it.
  case allProcesses
}
