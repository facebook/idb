/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBFileWriter)
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
    return FBDataConsumerAdaptor.dataConsumer(forDispatchDataConsumer: FBFileWriter_Null())
  }

  private static func fileDescriptor(forPath filePath: String) throws -> Int32 {
    let fd = open(filePath, O_WRONLY | O_CREAT, 0o644)
    if fd == -1 {
      throw
        FBControlCoreError
        .describe("A file handle for path \(filePath) could not be opened: \(String(cString: strerror(errno)))")
        .build()
    }
    return fd
  }

  @objc public static func asyncDispatchDataWriter(withFileDescriptor fileDescriptor: Int32, closeOnEndOfFile: Bool) -> FBFuture<AnyObject> {
    let writer = FBFileWriter_Async(fileDescriptor: fileDescriptor, closeOnEndOfFile: closeOnEndOfFile, writeQueue: createWorkQueue())
    do {
      try writer.startWriting()
    } catch {
      return FBFuture(error: error)
    }
    return FBFuture(result: writer)
  }

  @objc public static func syncWriter(withFileDescriptor fileDescriptor: Int32, closeOnEndOfFile: Bool) -> FBDataConsumer & FBDataConsumerLifecycle {
    return FBDataConsumerAdaptor.dataConsumer(forDispatchDataConsumer: FBFileWriter_Sync(fileDescriptor: fileDescriptor, closeOnEndOfFile: closeOnEndOfFile))
  }

  @objc public static func asyncWriter(withFileDescriptor fileDescriptor: Int32, closeOnEndOfFile: Bool, queue: DispatchQueue, error: NSErrorPointer) -> (FBDataConsumer & FBDataConsumerLifecycle)? {
    let writer = FBFileWriter_Async(fileDescriptor: fileDescriptor, closeOnEndOfFile: closeOnEndOfFile, writeQueue: queue)
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

  @objc public static func syncWriter(forFilePath filePath: String, error: NSErrorPointer) -> (FBDataConsumer & FBDataConsumerLifecycle & FBDataConsumerSync)? {
    let fd: Int32
    do {
      fd = try fileDescriptor(forPath: filePath)
    } catch let e {
      error?.pointee = e as NSError
      return nil
    }
    return FBFileWriter.syncWriter(withFileDescriptor: fd, closeOnEndOfFile: true) as? (FBDataConsumer & FBDataConsumerLifecycle & FBDataConsumerSync)
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
        let writer = FBFileWriter_Async(fileDescriptor: fd, closeOnEndOfFile: true, writeQueue: queue)
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

// MARK: - FBFileWriter_Null

private class FBFileWriter_Null: FBFileWriter, FBDispatchDataConsumer, FBDataConsumerLifecycle {

  func consumeData(_ data: __DispatchData) {
    // do nothing
  }

  func consumeEndOfFile() {
    finishedConsumingMutable.resolve(withResult: NSNull())
  }

  var finishedConsuming: FBFuture<NSNull> {
    return unsafeBitCast(finishedConsumingMutable, to: FBFuture<NSNull>.self)
  }
}

// MARK: - FBFileWriter_Sync

private class FBFileWriter_Sync: FBFileWriter, FBDispatchDataConsumer, FBDataConsumerLifecycle {

  func consumeData(_ data: __DispatchData) {
    let dispatchData = data as DispatchData
    dispatchData.enumerateBytes { buffer, _, _ in
      write(self.fileDescriptor, buffer.baseAddress!, buffer.count)
    }
  }

  func consumeEndOfFile() {
    finishedConsumingMutable.resolve(withResult: NSNull())
    if closeOnEndOfFile {
      close(fileDescriptor)
    }
  }

  var finishedConsuming: FBFuture<NSNull> {
    return unsafeBitCast(finishedConsumingMutable, to: FBFuture<NSNull>.self)
  }
}

// MARK: - FBFileWriter_Async

private class FBFileWriter_Async: FBFileWriter, FBDispatchDataConsumer, FBDataConsumerLifecycle {

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
    // We can't close the file handle right now since there may still be pending IO operations on the channel.
    // The safe place to do this is within the dispatch_io_create cleanup_handler callback.
    // We also want to ensure that there are no pending write operations on the channel.
    // The barrier ensures that there are no pending writes before we attempt to interrupt the channel.
    io.barrier {
      io.close(flags: .stop)
    }
  }

  var finishedConsuming: FBFuture<NSNull> {
    return unsafeBitCast(finishedConsumingMutable, to: FBFuture<NSNull>.self)
  }

  func startWriting() throws {
    assert(io == nil)

    let finishedConsuming = finishedConsumingMutable

    // Use weak self to avoid retain cycle (see comments in ObjC implementation)
    io = DispatchIO(type: .stream, fileDescriptor: fileDescriptor, queue: writeQueue) { [weak self] errorCode in
      self?.ioChannelDidClose(withError: errorCode)
      // Since writing is asynchronous, wait until the io channel is fully closed.
      finishedConsuming.resolve(withResult: NSNull())
    }
    guard io != nil else {
      throw
        FBControlCoreError
        .describe("A IO Channel could not be created for fd \(fileDescriptor)")
        .build()
    }

    // Report partial results with as little as 1 byte read.
    io?.setLimit(lowWater: 1)
  }

  private func ioChannelDidClose(withError errorCode: Int32) {
    io = nil
    if closeOnEndOfFile {
      close(fileDescriptor)
    }
  }
}
