/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public enum DefaultConfiguration {

  public static let cacheInvalidationInterval: TimeInterval = 120 // 2 mins

  public static let baseURL = "https://interngraph.intern.facebook.com/"

  public static let urlSessionConfiguration: URLSessionConfiguration = {
    let configuration = URLSessionConfiguration.default
    let fifteenSeconds: TimeInterval = 15
    configuration.timeoutIntervalForRequest = fifteenSeconds
    return configuration
  }()
}
