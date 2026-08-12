/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

public final class FBDataDownloadInput: NSObject, @unchecked Sendable {

  public let input: FBProcessInput<AnyObject>
  private var urlSessionTask: URLSessionTask!
  private let logger: FBControlCoreLogger

  public static func dataDownload(withURL url: URL, logger: FBControlCoreLogger) -> FBDataDownloadInput {
    return dataDownload(withURL: url, configuration: .default, logger: logger)
  }

  /// Downloads over a caller-supplied session configuration, so that timeouts,
  /// caching policy and protocol handling are the caller's to decide.
  public static func dataDownload(withURL url: URL, configuration: URLSessionConfiguration, logger: FBControlCoreLogger) -> FBDataDownloadInput {
    let download = FBDataDownloadInput(url: url, configuration: configuration, logger: logger)
    download.urlSessionTask.resume()
    return download
  }

  private init(url: URL, configuration: URLSessionConfiguration, logger: FBControlCoreLogger) {
    self.logger = logger
    let rawInput = FBProcessInput<NSObject>.fromConsumer()
    self.input = unsafeBitCast(rawInput, to: FBProcessInput<AnyObject>.self)
    super.init()
    let delegateQueue = OperationQueue()
    delegateQueue.name = "CompanionLib.FBDataDownloadInput.urlSessionDelegate"
    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
    self.urlSessionTask = session.dataTask(with: url)
  }
}

// MARK: - URLSessionDataDelegate

extension FBDataDownloadInput: URLSessionDataDelegate {

  public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    (input.contents as? FBDataConsumer)?.consumeData(data)
  }

  public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error {
      logger.error().log("Download task \(task) failed with error \(error)")
    }
    (input.contents as? FBDataConsumer)?.consumeEndOfFile()
  }
}
