/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

@objc public final class FBDataDownloadInput: NSObject, @unchecked Sendable {

  @objc public let input: FBProcessInput<AnyObject>
  private var urlSessionTask: URLSessionTask!
  private let logger: FBControlCoreLogger

  @objc(dataDownloadWithURL:logger:)
  public static func dataDownload(withURL url: URL, logger: FBControlCoreLogger) -> FBDataDownloadInput {
    let download = FBDataDownloadInput(url: url, logger: logger)
    download.urlSessionTask.resume()
    return download
  }

  private init(url: URL, logger: FBControlCoreLogger) {
    self.logger = logger
    let rawInput = FBProcessInput<NSObject>.fromConsumer()
    self.input = unsafeBitCast(rawInput, to: FBProcessInput<AnyObject>.self)
    super.init()
    let configuration = URLSessionConfiguration.default
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
