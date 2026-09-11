/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

enum FBFileWriterError: Error, LocalizedError {
  case openFailed(path: String, message: String)
  case ioChannelCreationFailed(fileDescriptor: Int32)

  public var errorDescription: String? {
    switch self {
    case let .openFailed(path, message):
      return "A file handle for path \(path) could not be opened: \(message)"
    case let .ioChannelCreationFailed(fileDescriptor):
      return "A IO Channel could not be created for fd \(fileDescriptor)"
    }
  }
}

@objc
public class FBFileWriter: NSObject {

  // MARK: - Properties

  fileprivate let fileDescriptor: Int32
  fileprivate let closeOnEndOfFile: Bool
  fileprivate var finishedConsumingMutable: FBMutableFuture<AnyObject>

  // MARK: - Initializers

  private static func createWorkQueue() -> DispatchQueue {
    return DispatchQueue(label: "com.facebook.fbcontrolcore.fbfilewriter")
  }

  @objc public static var nullWriter: FBDataConsumer {
    return FBDataConsumerAdaptor.dataConsumer(forDispatchDataConsumer: FileWriter_Null())
  }

  private static func fileDescriptor(forPath filePath: String) throws -> Int32 {
    let fd = open(filePath, O_WRONLY | O_CREAT, 0o644)
    if fd == -1 {
      throw FBFileWriterError.openFailed(path: filePath, message: String(cString: strerror(errno)))
    }
    return fd
  }

  @objc public static func asyncDispatchDataWriter(withFileDescriptor fileDescriptor: Int32, closeOnEndOfFile: Bool) -> FBFuture<AnyObject> {
    let writer = FileWriter_Async(fileDescriptor: fileDescriptor, closeOnEndOfFile: closeOnEndOfFile, writeQueue: createWorkQueue())
    do {
      try writer.startWriting()
    } catch {
      return FBFuture(error: error)
    }
    return FBFuture(result: writer)
  }

  @objc public static func syncWriter(withFileDescriptor fileDescriptor: Int32, closeOnEndOfFile: Bool) -> FBDataConsumer & FBDataConsumerLifecycle {
    return FBDataConsumerAdaptor.dataConsumer(forDispatchDataConsumer: FileWriter_Sync(fileDescriptor: fileDescriptor, closeOnEndOfFile: closeOnEndOfFile))
  }

  @objc public static func asyncWriter(withFileDescriptor fileDescriptor: Int32, closeOnEndOfFile: Bool, queue: DispatchQueue, error: NSErrorPointer) -> (FBDataConsumer & FBDataConsumerLifecycle)? {
    let writer = FileWriter_Async(fileDescriptor: fileDescriptor, closeOnEndOfFile: closeOnEndOfFile, writeQueue: queue)
    do {
      try writer.startWriting()
    } catch let e {
      error?.pointee = e as NSError
      return nil
    }
    return FBDataConsumerAdaptor.dataConsumer(forDispatchDataConsumer: writer)
  }

  @objc public static func asyncWriter(withFileDescriptor fileDescriptor: Int32, closeOnEndOfFile: Bool, error: NSErrorPointer) -> (FBDataConsumer & FBDataConsumerLifecycle)? {
    let queue = createWorkQueue()
    return asyncWriter(withFileDescriptor: fileDescriptor, closeOnEndOfFile: closeOnEndOfFile, queue: queue, error: error)
  }

  @objc public static func syncWriter(forFilePath filePath: String, error: NSErrorPointer) -> (FBDataConsumer & FBDataConsumerLifecycle)? {
    let fd: Int32
    do {
      fd = try fileDescriptor(forPath: filePath)
    } catch let e {
      error?.pointee = e as NSError
      return nil
    }
    return FBFileWriter.syncWriter(withFileDescriptor: fd, closeOnEndOfFile: true)
  }

  @objc public static func asyncWriter(forFilePath filePath: String) -> FBFuture<AnyObject> {
    let queue = createWorkQueue()
    return FBFuture<AnyObject>.onQueue(
      queue,
      resolve: {
        let fd: Int32
        do {
          fd = try fileDescriptor(forPath: filePath)
        } catch {
          return FBFuture(error: error)
        }
        let writer = FileWriter_Async(fileDescriptor: fd, closeOnEndOfFile: true, writeQueue: queue)
        do {
          try writer.startWriting()
        } catch {
          return FBFuture(error: error)
        }
        return FBFuture(result: FBDataConsumerAdaptor.dataConsumer(forDispatchDataConsumer: writer) as AnyObject)
      })
  }

  fileprivate init(fileDescriptor: Int32, closeOnEndOfFile: Bool) {
    self.fileDescriptor = fileDescriptor
    self.closeOnEndOfFile = closeOnEndOfFile
    self.finishedConsumingMutable = FBMutableFuture(name: "EOF Received")
    super.init()
  }

  fileprivate override convenience init() {
    self.init(fileDescriptor: -1, closeOnEndOfFile: false)
  }
}

// MARK: - FileWriter_Null

private class FileWriter_Null: FBFileWriter, FBDispatchDataConsumer, FBDataConsumerLifecycle {

  func consumeData(_ data: __DispatchData) {
  }

  func consumeEndOfFile() {
    finishedConsumingMutable.resolve(withResult: NSNull())
  }

  var finishedConsuming: FBFuture<NSNull> {
    return finishedConsumingMutable.retyped(FBFuture<NSNull>.self)
  }
}

// MARK: - FileWriter_Sync

private class FileWriter_Sync: FBFileWriter, FBDispatchDataConsumer, FBDataConsumerLifecycle, FBDataConsumerSync {

  func consumeData(_ data: __DispatchData) {
    let dispatchData = data as DispatchData
    dispatchData.enumerateBytes { buffer, _, _ in
      guard let baseAddress = buffer.baseAddress else { return }
      write(self.fileDescriptor, baseAddress, buffer.count)
    }
  }

  func consumeEndOfFile() {
    finishedConsumingMutable.resolve(withResult: NSNull())
    if closeOnEndOfFile {
      close(fileDescriptor)
    }
  }

  var finishedConsuming: FBFuture<NSNull> {
    return finishedConsumingMutable.retyped(FBFuture<NSNull>.self)
  }
}

// MARK: - FileWriter_Async

private class FileWriter_Async: FBFileWriter, FBDispatchDataConsumer, FBDataConsumerLifecycle {

  let writeQueue: DispatchQueue
  var io: DispatchIO?

  init(fileDescriptor: Int32, closeOnEndOfFile: Bool, writeQueue: DispatchQueue) {
    self.writeQueue = writeQueue
    super.init(fileDescriptor: fileDescriptor, closeOnEndOfFile: closeOnEndOfFile)
  }

  func consumeData(_ data: __DispatchData) {
    guard let io else { return }
    io.write(offset: 0, data: data as DispatchData, queue: writeQueue) { _, _, _ in }
  }

  func consumeEndOfFile() {
    guard let io else { return }
    // The descriptor is closed in the DispatchIO cleanup handler; the barrier ensures no writes are
    // pending before the channel is stopped.
    io.barrier {
      io.close(flags: .stop)
    }
  }

  var finishedConsuming: FBFuture<NSNull> {
    return finishedConsumingMutable.retyped(FBFuture<NSNull>.self)
  }

  func startWriting() throws {
    assert(io == nil)

    // O_NONBLOCK must be set before DispatchIO snapshots the descriptor flags; see
    // FBFileReader.startReadingNow for why.
    _ = fcntl(fileDescriptor, F_SETFL, fcntl(fileDescriptor, F_GETFL) | O_NONBLOCK)

    let finishedConsuming = finishedConsumingMutable

    io = DispatchIO(type: .stream, fileDescriptor: fileDescriptor, queue: writeQueue) { [weak self] errorCode in
      self?.ioChannelDidClose(withError: errorCode)
      // Since writing is asynchronous, wait until the io channel is fully closed.
      finishedConsuming.resolve(withResult: NSNull())
    }
    guard io != nil else {
      throw FBFileWriterError.ioChannelCreationFailed(fileDescriptor: fileDescriptor)
    }

    io?.setLimit(lowWater: 1)
  }

  private func ioChannelDidClose(withError errorCode: Int32) {
    io = nil
    if closeOnEndOfFile {
      close(fileDescriptor)
    }
  }
}
