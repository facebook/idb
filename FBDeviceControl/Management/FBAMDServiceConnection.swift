/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

private typealias HeaderIntType = UInt32
private let HeaderLength = MemoryLayout<HeaderIntType>.size

/// There is an upper limit on the number of bytes that can be moved at once.
private let ReadBufferSize = 1024 * 4
private let SendBufferSize = 1024 * 4

/// How long invalidation waits for an in-flight read loop to exit before the underlying connection
/// is released.
private let ReaderDrainTimeout: TimeInterval = 5

/// The ways a lockdown service connection can fail, as data rather than assembled strings.
public enum FBAMDServiceConnectionError: Error {
  case sendMessageFailed(errorText: String, message: String, code: Int32)
  case receiveMessageFailed(errorText: String, code: Int32)
  case noConnectionToInvalidate
  case invalidateFailed(connection: String, errorText: String)
  case sendFailed(bytes: Int, reason: String)
  case sentMoreThanRemained(sent: Int, remaining: Int)
  case sendIncomplete(requested: Int, remaining: Int)
  case receiveFailed(bytes: Int, reason: String)
  case readMoreThanRemained(read: Int, remaining: Int)
  case receiveIncomplete(requested: Int, remaining: Int)
  case receiveUpToFailed(size: Int, reason: String)
  case cannotStartReading(state: UInt)
  case cannotStopBeforeStarting
}

extension FBAMDServiceConnectionError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .sendMessageFailed(errorText, message, code):
      return "Failed to send message \(errorText) (\(message) code \(code))"
    case let .receiveMessageFailed(errorText, code):
      return "Failed to receive message (\(errorText)): code \(code)"
    case .noConnectionToInvalidate:
      return "No connection to invalidate"
    case let .invalidateFailed(connection, errorText):
      return "Failed to invalidate connection \(connection) with error \(errorText)"
    case let .sendFailed(bytes, reason):
      return "Failure in send of \(bytes) bytes: \(reason)"
    case let .sentMoreThanRemained(sent, remaining):
      return "Failure in send: Sent \(sent) bytes but only \(remaining) bytes remaining"
    case let .sendIncomplete(requested, remaining):
      return "Failed to send \(requested) bytes, \(remaining) remaining"
    case let .receiveFailed(bytes, reason):
      return "Failure in receive of \(bytes) bytes: \(reason)"
    case let .readMoreThanRemained(read, remaining):
      return "Failure in receive: Read \(read) bytes but only \(remaining) bytes remaining"
    case let .receiveIncomplete(requested, remaining):
      return "Failed to receive \(requested) bytes, \(remaining) remaining to read and eof reached."
    case let .receiveUpToFailed(size, reason):
      return "Failure in receive of up to \(size) bytes: \(reason)"
    case let .cannotStartReading(state):
      return "Cannot start reading in state \(state)"
    case .cannotStopBeforeStarting:
      return "Cannot stop reading when reading has not started"
    }
  }
}

/// Wraps the AMDServiceConnection.
///
/// An AMDServiceConnection represents a connection to a "lockdown" service over USB.
@objc(FBAMDServiceConnection)
public final class FBAMDServiceConnection: NSObject {

  // MARK: - Properties

  @objc public let name: String
  @objc public let device: AMDevice
  @objc public let calls: AMDCalls
  @objc public let logger: (any FBControlCoreLogger)?

  /// Held unretained: MobileDevice hands the connection over at +1 and `invalidate` is what gives
  /// that back. Retaining it here would leave the release unbalanced.
  private var connectionRef: Unmanaged<AnyObject>?

  private var activeReaderFinished: FBFuture<NSNumber>?

  @objc public var connection: AMDServiceConnection? {
    connectionRef?.takeUnretainedValue()
  }

  // MARK: - Initializers

  /// The Objective-C entry point; Swift callers use the initializer directly.
  @objc(connectionWithName:connection:device:calls:logger:)
  public class func connection(
    name: String,
    connection: AMDServiceConnection,
    device: AMDevice,
    calls: AMDCalls,
    logger: (any FBControlCoreLogger)?
  ) -> FBAMDServiceConnection {
    FBAMDServiceConnection(name: name, connection: connection, device: device, calls: calls, logger: logger)
  }

  @objc(initWithName:connection:device:calls:logger:)
  public init(
    name: String,
    connection: AMDServiceConnection,
    device: AMDevice,
    calls: AMDCalls,
    logger: (any FBControlCoreLogger)?
  ) {
    // Raw transfer is used when there is no secure context, otherwise the service connection
    // wrapping must be used.
    let secureIOContext = calls.ServiceConnectionGetSecureIOContext(connection)
    logger?.log("Constructing service connection for \(name) \(secureIOContext != nil ? "is" : "is not") Secure")
    self.name = name
    self.connectionRef = Unmanaged.passUnretained(connection as AnyObject)
    self.device = device
    self.calls = calls
    self.logger = logger
    super.init()
  }

  // MARK: - NSObject

  public override var description: String {
    "\(name) \(String(describing: connection))"
  }

  // MARK: - plist Messaging

  @objc(sendMessage:error:)
  public func sendMessage(_ message: Any) throws {
    let result = calls.ServiceConnectionSendMessage(
      connection, message as CFPropertyList, CFPropertyListFormat.binaryFormat_v1_0, nil, nil, nil)
    guard result == 0 else {
      throw FBAMDServiceConnectionError.sendMessageFailed(
        errorText: errorText(result), message: String(describing: message), code: result)
    }
  }

  @objc(receiveMessageWithError:)
  public func receiveMessage() throws -> Any {
    var message: Unmanaged<CFPropertyList>?
    let result = calls.ServiceConnectionReceiveMessage(connection, &message, nil, nil, nil, nil)
    guard result == 0 else {
      throw FBAMDServiceConnectionError.receiveMessageFailed(errorText: errorText(result), code: result)
    }
    return message?.takeRetainedValue() as Any
  }

  @objc(sendAndReceiveMessage:error:)
  public func sendAndReceiveMessage(_ message: Any) throws -> Any {
    try sendMessage(message)
    return try receiveMessage()
  }

  // MARK: - Lifecycle

  @objc(invalidateWithError:)
  public func invalidate() throws {
    guard let connectionRef else {
      throw FBAMDServiceConnectionError.noConnectionToInvalidate
    }
    let reference = connectionRef.takeUnretainedValue()
    let connectionDescription = CFCopyDescription(reference) as String? ?? "unknown"
    logger?.log("Invalidating Connection \(connectionDescription)")
    let status = calls.ServiceConnectionInvalidate(reference)
    guard status == 0 else {
      throw FBAMDServiceConnectionError.invalidateFailed(
        connection: connectionDescription, errorText: errorText(status))
    }
    logger?.log("Invalidated connection \(connectionDescription)")
    // The read loop may still be inside ServiceConnectionReceive; the invalidation above unblocks
    // it, but the connection must stay alive until the loop has actually exited — releasing it
    // mid-read reads freed memory inside the SSL layer.
    var drained = true
    if let activeReaderFinished {
      drained = (try? activeReaderFinished.await(withTimeout: ReaderDrainTimeout)) != nil
    }
    // AMDServiceConnectionInvalidate does not release the connection. If the reader failed to
    // drain in time the reference is deliberately leaked rather than released: releasing under a
    // still-blocked read is a use-after-free, and one leaked connection on a wedged service is
    // the cheaper failure.
    if drained {
      connectionRef.release()
    } else {
      logger?.log("Reader did not drain within \(ReaderDrainTimeout)s; leaking the connection rather than freeing it under an active read")
    }
    self.connectionRef = nil
  }

  // MARK: - AFC

  @objc(asAFCConnectionWithCalls:callback:logger:)
  public func asAFCConnection(
    calls afcCalls: AFCCalls,
    callback: @escaping AFCNotificationCallback,
    logger: any FBControlCoreLogger
  ) -> FBAFCConnection {
    let afcConnection = afcCalls.Create(nil, calls.ServiceConnectionGetSocket(connection), nil, callback, nil)
    // The secure context has to be applied if the service connection has one.
    let afcReference = afcConnection?.takeUnretainedValue()
    if let secureIOContext = calls.ServiceConnectionGetSecureIOContext(connection), let afcReference {
      afcCalls.SetSecureContext(afcReference, secureIOContext)
    }
    return FBAFCConnection(connection: afcReference, calls: afcCalls, logger: self.logger)
  }

  // MARK: - Sending

  @objc(send:error:)
  public func send(_ data: Data) throws {
    var bytesRemaining = data.count
    while bytesRemaining > 0 {
      let start = data.count - bytesRemaining
      let length = min(SendBufferSize, bytesRemaining)
      let result = data.withUnsafeBytes { buffer -> Int32 in
        // Only an empty payload has no base address, and the loop cannot be entered for one.
        guard let base = buffer.baseAddress else {
          return 0
        }
        return send(base.advanced(by: start), size: length)
      }
      if result == -1 {
        throw FBAMDServiceConnectionError.sendFailed(bytes: length, reason: String(cString: strerror(errno)))
      }
      // End of file.
      if result == 0 {
        break
      }
      let sentBytes = Int(result)
      guard sentBytes <= bytesRemaining else {
        throw FBAMDServiceConnectionError.sentMoreThanRemained(sent: sentBytes, remaining: bytesRemaining)
      }
      bytesRemaining -= sentBytes
    }
    guard bytesRemaining == 0 else {
      throw FBAMDServiceConnectionError.sendIncomplete(requested: data.count, remaining: bytesRemaining)
    }
  }

  @objc(sendWithLengthHeader:error:)
  public func send(withLengthHeader data: Data) throws {
    // The host length is converted to the endianness of the remote.
    let lengthWire = HeaderIntType(data.count).bigEndian
    try send(withUnsafeBytes(of: lengthWire) { Data($0) })
    try send(data)
  }

  @objc(sendUnsignedInt32:error:)
  public func sendUnsignedInt32(_ value: UInt32) throws {
    try send(withUnsafeBytes(of: value) { Data($0) })
  }

  // MARK: - Receiving

  @objc(receive:error:)
  public func receive(_ size: Int) throws -> Data {
    var data = Data()
    try enumerateReceive(ofLength: size, chunkSize: ReadBufferSize) { chunk in
      data.append(chunk)
    }
    return data
  }

  @objc(receive:toFile:error:)
  public func receive(_ size: Int, toFile fileHandle: FileHandle) throws {
    try enumerateReceive(ofLength: size, chunkSize: ReadBufferSize) { chunk in
      fileHandle.write(chunk)
    }
  }

  @objc(receive:ofSize:error:)
  public func receive(_ destination: UnsafeMutableRawPointer, ofSize size: Int) throws {
    let data = try receive(size)
    data.withUnsafeBytes { source in
      guard let base = source.baseAddress else { return }
      destination.copyMemory(from: base, byteCount: data.count)
    }
  }

  @objc(receiveUpTo:error:)
  public func receiveUp(to size: Int) throws -> Data {
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<UInt8>.alignment)
    defer { buffer.deallocate() }
    let result = receive(buffer, size: size)
    // End of file.
    if result == 0 {
      return Data()
    }
    if result == -1 {
      throw FBAMDServiceConnectionError.receiveUpToFailed(size: size, reason: String(cString: strerror(errno)))
    }
    return Data(bytes: buffer, count: Int(result))
  }

  @objc(receiveUnsignedInt32:error:)
  public func receiveUnsignedInt32(_ valueOut: UnsafeMutablePointer<UInt32>) throws {
    try receive(valueOut, ofSize: MemoryLayout<UInt32>.size)
  }

  @objc(receiveUnsignedInt64:error:)
  public func receiveUnsignedInt64(_ valueOut: UnsafeMutablePointer<UInt64>) throws {
    try receive(valueOut, ofSize: MemoryLayout<UInt64>.size)
  }

  // MARK: - Streams

  @objc(readFromConnectionWritingToConsumer:onQueue:)
  public func readFromConnectionWriting(
    to consumer: any FBDataConsumer,
    on queue: DispatchQueue
  ) -> any FBFileReaderProtocol {
    let reader = FBAMDServiceConnectionReader(connection: self, consumer: consumer, queue: queue)
    activeReaderFinished = reader.finishedReading
    return reader
  }

  @objc(writeWithConsumerWritingOnQueue:)
  public func writeWithConsumerWriting(on queue: DispatchQueue) -> any FBDataConsumer & FBDataConsumerLifecycle {
    FBBlockDataConsumer.asynchronousDataConsumer(on: queue) { [weak self] data in
      try? self?.send(data)
    }
  }

  // MARK: - Private

  fileprivate func send(_ buffer: UnsafeRawPointer, size: Int) -> Int32 {
    calls.ServiceConnectionSend(connection, buffer, size)
  }

  fileprivate func receive(_ buffer: UnsafeMutableRawPointer, size: Int) -> Int32 {
    calls.ServiceConnectionReceive(connection, buffer, size)
  }

  private func errorText(_ status: Int32) -> String {
    calls.CopyErrorText(status)?.takeRetainedValue() as String? ?? "Unknown error"
  }

  private func enumerateReceive(ofLength size: Int, chunkSize: Int, enumerator: (Data) -> Void) throws {
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunkSize, alignment: MemoryLayout<UInt8>.alignment)
    defer { buffer.deallocate() }

    var bytesRemaining = size
    while bytesRemaining > 0 {
      let maxReadBytes = min(chunkSize, bytesRemaining)
      let result = receive(buffer, size: maxReadBytes)
      // End of file.
      if result == 0 {
        break
      }
      if result == -1 {
        throw FBAMDServiceConnectionError.receiveFailed(
          bytes: maxReadBytes, reason: String(cString: strerror(errno)))
      }
      let readBytes = Int(result)
      guard readBytes <= bytesRemaining else {
        throw FBAMDServiceConnectionError.readMoreThanRemained(read: readBytes, remaining: bytesRemaining)
      }
      bytesRemaining -= readBytes
      enumerator(Data(bytesNoCopy: buffer, count: readBytes, deallocator: .none))
    }

    guard bytesRemaining == 0 else {
      throw FBAMDServiceConnectionError.receiveIncomplete(requested: size, remaining: bytesRemaining)
    }
  }
}

/// Reads a service connection until it is exhausted, feeding a consumer.
private final class FBAMDServiceConnectionReader: NSObject, FBFileReaderProtocol {

  private let connection: FBAMDServiceConnection
  private let consumer: any FBDataConsumer
  private let queue: DispatchQueue
  private let finishedReadingMutable: FBMutableFuture<NSNumber>

  /// Locked rather than a bare stored property: the read loop polls this from its queue while
  /// `stopReading` writes it from whichever thread the caller is on.
  private let stateLock = NSLock()
  private var stateStorage: FBFileReaderState

  private(set) var state: FBFileReaderState {
    get {
      stateLock.lock()
      defer { stateLock.unlock() }
      return stateStorage
    }
    set {
      stateLock.lock()
      defer { stateLock.unlock() }
      stateStorage = newValue
    }
  }

  init(connection: FBAMDServiceConnection, consumer: any FBDataConsumer, queue: DispatchQueue) {
    self.connection = connection
    self.consumer = consumer
    self.queue = queue
    self.stateStorage = .notStarted
    self.finishedReadingMutable = FBMutableFuture<NSNumber>()
    super.init()
  }

  var finishedReading: FBFuture<NSNumber> {
    finishedReadingMutable.retyped(FBFuture<NSNumber>.self)
  }

  func startReading() -> FBFuture<NSNull> {
    guard state == .notStarted else {
      return FBFuture<NSNull>(error: FBAMDServiceConnectionError.cannotStartReading(state: state.rawValue) as NSError)
    }

    queue.async { [self] in
      let buffer = UnsafeMutableRawPointer.allocate(byteCount: ReadBufferSize, alignment: MemoryLayout<UInt8>.alignment)
      defer { buffer.deallocate() }
      while state == .reading && finishedReadingMutable.state == .running {
        let readBytes = connection.receive(buffer, size: ReadBufferSize)
        if readBytes < 1 {
          break
        }
        consumer.consumeData(Data(bytes: buffer, count: Int(readBytes)))
      }
      consumer.consumeEndOfFile()
      state = .finishedReadingNormally
      // Resolution is tolerant of stopReading having resolved first; without this, waiters on
      // natural end-of-file hang forever.
      finishedReadingMutable.resolve(withResult: NSNumber(value: FBFileReaderState.finishedReadingNormally.rawValue))
    }
    state = .reading

    return FBFuture<NSNull>.empty()
  }

  func stopReading() -> FBFuture<NSNumber> {
    if state == .notStarted {
      return FBFuture<NSNumber>(error: FBAMDServiceConnectionError.cannotStopBeforeStarting as NSError)
    }
    if state != .reading {
      return finishedReading
    }
    state = .finishedReadingByCancellation
    finishedReadingMutable.resolve(
      withResult: NSNumber(value: FBFileReaderState.finishedReadingByCancellation.rawValue))
    return finishedReading
  }

  func finishedReading(withTimeout timeout: TimeInterval) -> FBFuture<NSNumber> {
    finishedReading
      .timeout(timeout, waitingFor: "Process Reading to Finish")
      .onQueue(queue, handleError: { _ in self.stopReading().retyped(FBFuture<AnyObject>.self) })
      .retyped(FBFuture<NSNumber>.self)
  }
}
