/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A transfer whose body is written to a spool as it arrives: `DataDownloadInput` over `URLSession`, or
/// `NetworkDownloadInput` when the connection goes to a `ConnectionOverride`.
protocol DownloadInput: Sendable {

  /// The downloaded bytes, written as they arrive and ended when the transfer ends.
  var spool: DownloadSpool { get }

  /// Waits for the transfer to finish, throwing if it failed.
  @discardableResult
  func completed() async throws -> DownloadReport

  /// Stops the transfer, which then completes failed and ends `spool`.
  func cancel()

  /// Whether the download failed for a reason of its own, rather than because `cancel` stopped it.
  var failedOnItsOwn: Bool { get }
}

extension DataDownloadInput: DownloadInput {}
