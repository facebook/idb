/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Swift-native async/await counterpart of `FBScreenshotCommands`.
public protocol AsyncScreenshotCommands: AnyObject {

  func takeScreenshot(format: FBScreenshotFormat) async throws -> Data
}

/// Default bridge implementation against the legacy `FBScreenshotCommands`
/// protocol.
extension AsyncScreenshotCommands where Self: FBScreenshotCommands {

  public func takeScreenshot(format: FBScreenshotFormat) async throws -> Data {
    let data = try await bridgeFBFuture(self.takeScreenshot(format))
    return data as Data
  }
}
