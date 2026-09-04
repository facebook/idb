/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import Foundation

/// Writes `data` straight to the stdout file descriptor, bypassing stdio. A short or failed write is
/// not reported; the stdout protocol has no way to signal one.
func writeToStandardOutput(_ data: Data) {
  data.withUnsafeBytes { bytes in
    guard let baseAddress = bytes.baseAddress else { return }
    _ = Darwin.write(STDOUT_FILENO, baseAddress, bytes.count)
  }
}
