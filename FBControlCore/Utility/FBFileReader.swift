/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

private func stateString(from state: FBFileReaderState) -> String {
  switch state {
  case .notStarted:
    return "Not Started"
  case .reading:
    return "Reading"
  case .finishedReadingNormally:
    return "Finished Reading Normally"
  case .finishedReadingInError:
    return "Finished Reading in Error"
  case .finishedReadingByCancellation:
    return "Finished Reading in Cancellation"
  @unknown default:
    return "Unknown"
  }
}

public enum FBFileReaderError: Error, LocalizedError {
  case openFailed(path: String, message: String)
  case wrongStateToStart(targeting: String, state: String)
  case ioChannelCreationFailed(description: String)
  case notStartedReading(targeting: String)

  public var errorDescription: String? {
    switch self {
    case let .openFailed(path, message):
      return "open of \(path) returned an error '\(message)'"
    case let .wrongStateToStart(targeting, state):
      return "Could not start reading read of \(targeting) when it is in state \(state)"
    case let .ioChannelCreationFailed(description):
      return "A IO Channel could not be created for \(description)"
    case let .notStartedReading(targeting):
      return "File reader has not started reading \(targeting), you should call 'startReading' first"
    }
  }
}

@objc(FBFileReader)
public final class FBFileReader: NSObject, FBFileReaderProtocol {

  // MARK: - Private Properties

  private let targeting: String
  private let consumer: FBDispatchDataConsumer
  private let readQueue: DispatchQueue
  private let ioChannelRelinquishedControl: FBMutableFuture<AnyObject>
  private let fileDescriptor: Int32
  private let closeOnEndOfFile: Bool
  private let logger: FBControlCoreLogger?

  @objc public private(set) var state: FBFileReaderState
  private var io: DispatchIO?

  // MARK: - Initializers

  private static func createQueue() -> DispatchQueue {
    DispatchQueue(label: "com.facebook.fbcontrolcore.fbfilereader")
  }

  @objc public static func reader(withFileDescriptor fileDescriptor: Int32, closeOnEndOfFile: Bool, consumer: FBDataConsumer, logger: FBControlCoreLogger?) -> Self {
    dispatchDataReader(withFileDescriptor: fileDescriptor, closeOnEndOfFile: closeOnEndOfFile, consumer: FBDataConsumerAdaptor.dispatchDataConsumer(for: consumer), logger: logger)
  }

  @objc public static func dispatchDataReader(withFileDescriptor fileDescriptor: Int32, closeOnEndOfFile: Bool, consumer: FBDispatchDataConsumer, logger: FBControlCoreLogger?) -> Self {
    let targeting = "fd \(fileDescriptor)"
    return self.init(fileDescriptor: fileDescriptor, closeOnEndOfFile: closeOnEndOfFile, consumer: consumer, targeting: targeting, queue: createQueue(), logger: logger)
  }

  @objc public static func reader(withFilePath filePath: String, consumer: FBDataConsumer, logger: FBControlCoreLogger?) -> FBFuture<FBFileReader> {
    let queue = createQueue()
    return unsafeBitCast(
      FBFuture<AnyObject>.onQueue(
        queue,
        resolve: {
          let fd = open(filePath, O_RDONLY)
          if fd == -1 {
            return FBFuture(error: FBFileReaderError.openFailed(path: filePath, message: String(cString: strerror(errno))))
          }
          return FBFuture(
            result: FBFileReader(
              fileDescriptor: fd,
              closeOnEndOfFile: true,
              consumer: FBDataConsumerAdaptor.dispatchDataConsumer(for: consumer),
              targeting: filePath,
              queue: queue,
              logger: logger
            ))
        }),
      to: FBFuture<FBFileReader>.self
    )
  }

  required init(fileDescriptor: Int32, closeOnEndOfFile: Bool, consumer: FBDispatchDataConsumer, targeting: String, queue: DispatchQueue, logger: FBControlCoreLogger?) {
    self.fileDescriptor = fileDescriptor
    self.consumer = consumer
    self.targeting = targeting
    self.readQueue = queue
    self.ioChannelRelinquishedControl = FBMutableFuture(name: "IO Channel control relinquished \(targeting)")
    self.logger = logger
    self.state = .notStarted
    self.closeOnEndOfFile = closeOnEndOfFile
    super.init()
  }

  // MARK: - NSObject

  public override var description: String {
    "Reader for \(targeting) with state \(stateString(from: state))"
  }

  // MARK: - Public Methods

  @objc public func startReading() -> FBFuture<NSNull> {
    return unsafeBitCast(
      FBFuture<AnyObject>.onQueue(
        readQueue,
        resolve: {
          self.startReadingNow()
        }),
      to: FBFuture<NSNull>.self
    )
  }

  @objc public func stopReading() -> FBFuture<NSNumber> {
    return unsafeBitCast(
      FBFuture<AnyObject>.onQueue(
        readQueue,
        resolve: {
          self.stopReadingNow()
        }),
      to: FBFuture<NSNumber>.self
    )
  }

  @objc public func finishedReading(withTimeout timeout: TimeInterval) -> FBFuture<NSNumber> {
    return unsafeBitCast(
      finishedReading
        .onQueue(readQueue, timeout: timeout) {
          self.stopReadingNow()
        },
      to: FBFuture<NSNumber>.self
    )
  }

  @objc public var finishedReading: FBFuture<NSNumber> {
    // A fresh future, so cancelling the returned future does not cancel `ioChannelRelinquishedControl`.
    let future: FBMutableFuture<AnyObject> = FBMutableFuture(name: "Finished reading of \(targeting)")
    future.resolve(from: ioChannelRelinquishedControl)
    return unsafeBitCast(
      (future as FBFuture<AnyObject>)
        .onQueue(
          readQueue,
          respondToCancellation: {
            unsafeBitCast(self.stopReadingNow(), to: FBFuture<NSNull>.self)
          }),
      to: FBFuture<NSNumber>.self
    )
  }

  // MARK: - Private

  private func startReadingNow() -> FBFuture<AnyObject> {
    if state != .notStarted {
      return FBFuture(error: FBFileReaderError.wrongStateToStart(targeting: targeting, state: stateString(from: state)))
    }
    assert(io == nil, "IO Channel should not exist when not started")

    let consumer = self.consumer
    var readErrorCode: Int32 = 0

    // Set O_NONBLOCK before DispatchIO snapshots the descriptor flags: libdispatch restores that
    // snapshot asynchronously on teardown through the shared open file description (or a recycled
    // descriptor number), and a snapshot without O_NONBLOCK would wedge an unrelated live channel in
    // a blocking read(2).
    _ = fcntl(fileDescriptor, F_SETFL, fcntl(fileDescriptor, F_GETFL) | O_NONBLOCK)

    // If there is an error creating the IO Object, the errorCode will be delivered asynchronously.
    // The self-capture is intentional - we need to keep it alive until the IO channel is done.
    io = DispatchIO(type: .stream, fileDescriptor: fileDescriptor, queue: readQueue) { createErrorCode in
      self.ioChannelHasRelinquishedControl(withErrorCode: createErrorCode != 0 ? createErrorCode : readErrorCode)
    }
    guard let io else {
      return FBFuture(error: FBFileReaderError.ioChannelCreationFailed(description: self.description))
    }

    // Report partial results with as little as 1 byte read.
    io.setLimit(lowWater: 1)
    io.read(offset: 0, length: Int.max, queue: readQueue) { done, data, errorCode in
      if let data, !data.isEmpty {
        consumer.consumeData(data as __DispatchData)
      }
      if done {
        readErrorCode = Int32(errorCode)
        self.ioChannelReadOperationDone(Int32(errorCode))
      }
    }
    state = .reading
    return unsafeBitCast(FBFuture<NSNull>.empty(), to: FBFuture<AnyObject>.self)
  }

  private func stopReadingNow() -> FBFuture<AnyObject> {
    if state == .notStarted {
      return FBFuture(error: FBFileReaderError.notStartedReading(targeting: targeting))
    }
    if state != .reading {
      return ioChannelRelinquishedControl
    }

    // dispatch_io_close will stop future reads of the io channel.
    io?.close(flags: .stop)
    return ioChannelRelinquishedControl
  }

  private func ioChannelReadOperationDone(_ errorCode: Int32) {
    ioChannelReadOperationStateFinalize(errorCode)

    // Closing is necessary when a read has finished, since a "Read Operation" terminating *does not* mean
    // that the channel control has been relinquished.
    guard let io else { return }
    io.close()
  }

  private func ioChannelHasRelinquishedControl(withErrorCode errorCode: Int32) {
    // In the case of a bad file descriptor (EBADF) this can be called before dispatch_io_read.
    ioChannelReadOperationStateFinalize(errorCode)

    ioChannelRelinquishedControl.resolve(withResult: NSNumber(value: errorCode))

    guard io != nil else { return }
    io = nil
    if closeOnEndOfFile {
      close(fileDescriptor)
    }
  }

  private func ioChannelReadOperationStateFinalize(_ errorCode: Int32) {
    // Should only be called in response to 'done' flagging on dispatch_io_read
    if state != .reading {
      return
    }
    switch errorCode {
    case 0:
      state = .finishedReadingNormally
    case Int32(ECANCELED):
      state = .finishedReadingByCancellation
    default:
      state = .finishedReadingInError
    }
    consumer.consumeEndOfFile()
  }
}
