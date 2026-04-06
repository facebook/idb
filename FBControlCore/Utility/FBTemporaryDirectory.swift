/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBTemporaryDirectory)
public class FBTemporaryDirectory: NSObject {

  // MARK: Properties

  @objc public let logger: FBControlCoreLogger
  @objc public let queue: DispatchQueue

  private let rootTemporaryDirectory: URL

  // MARK: Initializers

  @objc(temporaryDirectoryWithLogger:)
  public class func temporaryDirectory(logger: FBControlCoreLogger) -> Self {
    var base = ProcessInfo.processInfo.environment["TMPDIR"]
    if base == nil {
      base = NSTemporaryDirectory()
    }
    let tempPathComponents = [base!, "IDB", UUID().uuidString]
    let temporaryDirectory = NSURL.fileURL(withPathComponents: tempPathComponents)!
    var error: NSError?
    let success: Bool
    do {
      try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true, attributes: nil)
      success = true
    } catch let err as NSError {
      error = err
      success = false
    }
    assert(success, "\(error!)")
    let queue = DispatchQueue(label: "com.facebook.idb.fbtemporarydirectory")
    return self.init(rootDirectory: temporaryDirectory, queue: queue, logger: logger)
  }

  @objc(initWithLogger:)
  public convenience init(logger: FBControlCoreLogger) {
    var base = ProcessInfo.processInfo.environment["TMPDIR"]
    if base == nil {
      base = NSTemporaryDirectory()
    }
    let tempPathComponents = [base!, "IDB", UUID().uuidString]
    let temporaryDirectory = NSURL.fileURL(withPathComponents: tempPathComponents)!
    do {
      try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true, attributes: nil)
    } catch {
      fatalError("Failed to create temporary directory: \(error)")
    }
    let queue = DispatchQueue(label: "com.facebook.idb.fbtemporarydirectory")
    self.init(rootDirectory: temporaryDirectory, queue: queue, logger: logger)
  }

  required init(rootDirectory: URL, queue: DispatchQueue, logger: FBControlCoreLogger) {
    self.rootTemporaryDirectory = rootDirectory
    self.queue = queue
    self.logger = logger
    super.init()
  }

  // MARK: Public Methods

  @objc public func cleanOnExit() {
    do {
      try FileManager.default.removeItem(at: rootTemporaryDirectory)
      logger.debug().log("Successfully removed temporal directory: \(rootTemporaryDirectory)")
    } catch {
      logger.error().log("Couldn't remove temporary directory: \(rootTemporaryDirectory) (\(error.localizedDescription))")
    }
  }

  @objc public func ephemeralTemporaryDirectory() -> URL {
    return rootTemporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  @objc(withGzipExtractedFromStream:name:)
  public func withGzipExtracted(fromStream input: FBProcessInput<AnyObject>, name: String) -> FBFutureContext<NSURL> {
    return withTemporaryFileNamed(name)
      .onQueue(queue, pend: { result -> FBFuture<AnyObject> in
        let resultURL = result as URL
        return FBArchiveOperations.extractGzip(fromStream: input, toPath: resultURL.path, logger: self.logger)
          .mapReplace(resultURL as NSURL)
      }) as! FBFutureContext<NSURL>
  }

  @objc(withArchiveExtracted:)
  public func withArchiveExtracted(_ tarData: Data) -> FBFutureContext<NSURL> {
    let input = unsafeBitCast(FBProcessInput<NSData>(from: tarData), to: FBProcessInput<AnyObject>.self)
    return withArchiveExtracted(fromStream: input, compression: .GZIP)
  }

  @objc(withArchiveExtractedFromStream:compression:)
  public func withArchiveExtracted(fromStream input: FBProcessInput<AnyObject>, compression: FBCompressionFormat) -> FBFutureContext<NSURL> {
    return withArchiveExtracted(fromStream: input, compression: compression, overrideModificationTime: false)
  }

  @objc(withArchiveExtractedFromStream:compression:overrideModificationTime:)
  public func withArchiveExtracted(fromStream input: FBProcessInput<AnyObject>, compression: FBCompressionFormat, overrideModificationTime overrideMTime: Bool) -> FBFutureContext<NSURL> {
    return withTemporaryDirectory()
      .onQueue(queue, pend: { result -> FBFuture<AnyObject> in
        let tempDir = result as URL
        return FBArchiveOperations.extractArchive(fromStream: input, toPath: tempDir.path, overrideModificationTime: overrideMTime, logger: self.logger, compression: compression)
          .mapReplace(tempDir as NSURL)
      }) as! FBFutureContext<NSURL>
  }

  @objc(withArchiveExtractedFromFile:)
  public func withArchiveExtracted(fromFile filePath: String) -> FBFutureContext<NSURL> {
    return withArchiveExtracted(fromFile: filePath, overrideModificationTime: false)
  }

  @objc(withArchiveExtractedFromFile:overrideModificationTime:)
  public func withArchiveExtracted(fromFile filePath: String, overrideModificationTime overrideMTime: Bool) -> FBFutureContext<NSURL> {
    return withTemporaryDirectory()
      .onQueue(queue, pend: { result -> FBFuture<AnyObject> in
        let tempDir = result as URL
        return FBArchiveOperations.extractArchive(atPath: filePath, toPath: tempDir.path, overrideModificationTime: overrideMTime, logger: self.logger)
          .mapReplace(tempDir as NSURL)
      }) as! FBFutureContext<NSURL>
  }

  @objc(filesFromSubdirs:)
  public func files(fromSubdirs extractionDirContext: FBFutureContext<NSURL>) -> FBFutureContext<NSArray> {
    return extractionDirContext
      .onQueue(queue, pend: { result -> FBFuture<AnyObject> in
        let extractionDir = result as URL
        do {
          let subfolders = try FBStorageUtils.files(inDirectory: extractionDir)
          var filesInTar: [URL] = []
          for subfolder in subfolders {
            let file = try FBStorageUtils.findUniqueFile(inDirectory: subfolder)
            filesInTar.append(file)
          }
          return FBFuture<AnyObject>(result: filesInTar as NSArray)
        } catch {
          return FBFuture<AnyObject>(error: error as NSError)
        }
      }) as! FBFutureContext<NSArray>
  }

  // MARK: Temporary Directory

  @objc public func temporaryDirectory() -> URL {
    let tempDirectory = ephemeralTemporaryDirectory()
    logger.log("Creating Temp Dir \(tempDirectory)")
    do {
      try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
    } catch {
      logger.log("Failed to create Temp Dir \(tempDirectory) with error \(error)")
    }
    return tempDirectory
  }

  @objc public func withTemporaryDirectory() -> FBFutureContext<NSURL> {
    let tempDirectory = ephemeralTemporaryDirectory()
    logger.log("Creating Temp Dir \(tempDirectory)")
    do {
      try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
    } catch {
      return FBControlCoreError
        .describe("Failed to create Temp Dir \(tempDirectory)")
        .caused(by: error as NSError)
        .failFutureContext() as! FBFutureContext<NSURL>
    }
    return FBFuture<NSURL>(result: tempDirectory as NSURL)
      .onQueue(queue, contextualTeardown: { (result, _) -> FBFuture<NSNull> in
        let dirURL = result as URL
        do {
          try FileManager.default.removeItem(at: dirURL)
          self.logger.log("Deleted Temp Dir \(dirURL)")
        } catch {
          self.logger.log("Failed to delete Temp Dir \(dirURL): \(error)")
        }
        return FBFuture<NSNull>.empty()
      })
  }

  // MARK: Private

  private func withTemporaryFileNamed(_ name: String) -> FBFutureContext<NSURL> {
    return withTemporaryDirectory()
      .onQueue(queue, pend: { result -> FBFuture<AnyObject> in
        let directory = result as URL
        let tempFile = directory.appendingPathComponent(name)
        return FBFuture<AnyObject>(result: tempFile as NSURL)
      })
      .onQueue(queue, contextualTeardown: { (result, _) -> FBFuture<NSNull> in
        let tempFile = result as! URL
        do {
          try FileManager.default.removeItem(at: tempFile)
          self.logger.log("Deleted Temp File \(tempFile)")
        } catch {
          self.logger.log("Failed to delete Temp File \(tempFile): \(error)")
        }
        return FBFuture<NSNull>.empty()
      }) as! FBFutureContext<NSURL>
  }
}
