// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

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
