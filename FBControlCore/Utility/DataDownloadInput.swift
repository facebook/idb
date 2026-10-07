/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// What a download reports about its own progress, as distinct from the bytes it
/// is delivering.
public enum DataDownloadEvent: Sendable {

  /// The server accepted the request. A length of zero or less means it did not
  /// say how much to expect.
  case response(expectedContentLength: Int64)

  /// A chunk of this many bytes arrived.
  case data(byteCount: Int)
}

public final class DataDownloadInput: NSObject, @unchecked Sendable {

  /// The downloaded bytes, written as they arrive and finished when the transfer ends.
  public let pipe = BytePipe()

  /// Waits for the transfer to finish, throwing if the server rejected the request or the connection
  /// dropped. `pipe` alone cannot distinguish a failed download from a short one.
  @discardableResult
  public func completed() async throws -> DownloadReport {
    _ = try await bridgeFBFuture(completedFuture)
    // The future resolves on the delegate queue after the last write to `report`.
    return report
  }

  private let completedFuture: FBMutableFuture<NSNull>
  // Written only from the session's delegate queue, which is serial.
  private var report = DownloadReport()
  // The download starts as soon as it is made.
  private let requestStart = Date()
  private let onEvent: (@Sendable (DataDownloadEvent) -> Void)?
  private let logger: ControlCoreLogger

  public static func dataDownload(withURL url: URL, logger: ControlCoreLogger) -> DataDownloadInput {
    return dataDownload(withURL: url, configuration: .default, logger: logger)
  }

  /// Downloads over a caller-supplied session configuration, so that timeouts,
  /// caching policy and protocol handling are the caller's to decide.
  ///
  /// `onEvent` reports how many bytes have arrived, while the bytes themselves
  /// still go only to `pipe`, so a caller can show progress without getting
  /// between the download and whatever is consuming it.
  public static func dataDownload(
    withURL url: URL,
    configuration: URLSessionConfiguration,
    logger: ControlCoreLogger,
    onEvent: (@Sendable (DataDownloadEvent) -> Void)? = nil
  ) -> DataDownloadInput {
    let download = DataDownloadInput(logger: logger, onEvent: onEvent)
    download.startDownload(from: url, configuration: configuration)
    return download
  }

  private init(
    logger: ControlCoreLogger,
    onEvent: (@Sendable (DataDownloadEvent) -> Void)?
  ) {
    self.logger = logger
    self.onEvent = onEvent
    self.completedFuture = FBMutableFuture<NSNull>()
    super.init()
  }

  // The session holds both the delegate and the resumed task for the lifetime of the download, so neither needs storing here.
  // It lets go of the delegate only once invalidated, which `finishTasksAndInvalidate` defers until the task completes.
  private func startDownload(from url: URL, configuration: URLSessionConfiguration) {
    let delegateQueue = OperationQueue()
    delegateQueue.name = "FBControlCore.DataDownloadInput.urlSessionDelegate"
    // Callers read the events as an ordered sequence: the response before any
    // chunk, and chunks in arrival order. An `OperationQueue` is concurrent
    // unless told otherwise.
    delegateQueue.maxConcurrentOperationCount = 1
    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
    session.dataTask(with: url).resume()
    session.finishTasksAndInvalidate()
  }
}

// MARK: - URLSessionDataDelegate

extension DataDownloadInput: URLSessionDataDelegate {

  public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
    report.timeToFirstByte = Date().timeIntervalSince(requestStart)
    guard let httpResponse = response as? HTTPURLResponse else {
      completionHandler(.allow)
      return
    }
    guard httpResponse.statusCode == 200 else {
      // Without this the body of an error page is piped onward as though it were
      // the payload, and the caller is told it has a malformed archive.
      let error = InstallError.httpStatus(
        url: dataTask.originalRequest?.url ?? httpResponse.url,
        statusCode: httpResponse.statusCode)
      logger.error().log(error.description)
      completedFuture.resolveWithError(error)
      completionHandler(.cancel)
      return
    }
    onEvent?(.response(expectedContentLength: httpResponse.expectedContentLength))
    completionHandler(.allow)
  }

  public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    pipe.input.write(data)
    report.receivedBytes += Int64(data.count)
    onEvent?(.data(byteCount: data.count))
  }

  // Delivered before the task completes.
  public func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
    report.observe(metrics)
  }

  public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error {
      logger.error().log("Download task \(task) failed with error \(error)")
      report.trust = DownloadReport.Trust.evaluating(failure: error)
      // First resolution wins, so a cancellation triggered by a rejected response
      // does not displace the HTTP status that caused it.
      completedFuture.resolveWithError(
        InstallError.transferFailed(url: task.originalRequest?.url, underlying: error, report: report))
    } else {
      _ = completedFuture.resolve(withResult: NSNull())
    }
    pipe.input.finish()
  }
}
