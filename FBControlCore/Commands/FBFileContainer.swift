/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBFileContainerProtocol: NSObjectProtocol {

  @objc(copyFromHost:toContainer:)
  func copy(fromHost sourcePath: String, toContainer destinationPath: String) -> FBFuture<NSNull>

  @objc(copyFromContainer:toHost:)
  func copy(fromContainer sourcePath: String, toHost destinationPath: String) -> FBFuture<NSString>

  @objc(tail:toConsumer:)
  func tail(_ path: String, to consumer: FBDataConsumer) -> FBFuture<FBFuture<NSNull>>

  @objc(createDirectory:)
  func createDirectory(_ directoryPath: String) -> FBFuture<NSNull>

  @objc(moveFrom:to:)
  func move(from sourcePath: String, to destinationPath: String) -> FBFuture<NSNull>

  @objc(remove:)
  func remove(_ path: String) -> FBFuture<NSNull>

  @objc(contentsOfDirectory:)
  func contents(ofDirectory path: String) -> FBFuture<NSArray>
}

@objc public protocol FBContainedFile: NSObjectProtocol {

  @objc(removeItemWithError:)
  func removeItem() throws

  @objc(contentsOfDirectoryWithError:)
  func contentsOfDirectory() throws -> [String]

  @objc(contentsOfFileWithError:)
  func contentsOfFile() throws -> Data

  @objc(createDirectoryWithError:)
  func createDirectory() throws

  @objc(fileExistsIsDirectory:)
  func fileExists(isDirectory isDirectoryOut: UnsafeMutablePointer<ObjCBool>?) -> Bool

  @objc(moveTo:error:)
  func move(to destination: FBContainedFile) throws

  @objc(populateWithContentsOfHostPath:error:)
  func populate(withContentsOfHostPath path: String) throws

  @objc(populateHostPathWithContents:error:)
  func populateHostPath(withContents path: String) throws

  @objc(fileByAppendingPathComponent:error:)
  func file(byAppendingPathComponent component: String) throws -> FBContainedFile

  @objc var pathOnHostFileSystem: String? { get }

  @objc var pathMapping: [String: String]? { get }
}
