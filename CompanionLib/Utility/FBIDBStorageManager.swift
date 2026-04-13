/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import XCTestBootstrap

public let IdbTestBundlesFolder: String = "idb-test-bundles"
public let IdbApplicationsFolder: String = "idb-applications"
public let IdbDylibsFolder: String = "idb-dylibs"
public let IdbDsymsFolder: String = "idb-dsyms"
public let IdbFrameworksFolder: String = "idb-frameworks"

// MARK: - FBInstalledArtifact

@objc public final class FBInstalledArtifact: NSObject {
  @objc public let name: String
  @objc public let uuid: NSUUID?
  @objc public let path: URL

  @objc public init(name: String, uuid: NSUUID?, path: URL) {
    self.name = name
    self.uuid = uuid
    self.path = path
    super.init()
  }
}

// MARK: - FBIDBStorage

@objc public class FBIDBStorage: NSObject {
  @objc public let target: FBiOSTarget
  @objc public let basePath: URL
  @objc public let queue: DispatchQueue
  @objc public let logger: FBControlCoreLogger

  @objc public init(target: FBiOSTarget, basePath: URL, queue: DispatchQueue, logger: FBControlCoreLogger) {
    self.target = target
    self.basePath = basePath
    self.queue = queue
    self.logger = logger
    super.init()
  }

  @objc public func clean() throws {
    let urls = try FileManager.default.contentsOfDirectory(at: basePath, includingPropertiesForKeys: nil, options: [])
    for url in urls {
      try FileManager.default.removeItem(atPath: url.path)
    }
  }

  @objc public func asFileContainer() -> FBFileContainerProtocol {
    return FBFileContainer.fileContainer(forBasePath: basePath.path)
  }

  @objc public var replacementMapping: [String: String] {
    var mapping: [String: String] = [:]
    let urls = try? FileManager.default.contentsOfDirectory(at: basePath, includingPropertiesForKeys: nil, options: [])
    if let urls {
      for url in urls {
        mapping[url.lastPathComponent] = url.path
      }
    }
    return mapping
  }
}

// MARK: - FBFileStorage

@objc public final class FBFileStorage: FBIDBStorage {

  @objc public func saveFile(_ url: URL) throws -> FBInstalledArtifact {
    return try copyInto(basePath, from: url)
  }

  @objc public func saveFileInUniquePath(_ url: URL) throws -> FBInstalledArtifact {
    var baseURL = basePath
    baseURL = baseURL.appendingPathComponent(NSUUID().uuidString)
    try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true, attributes: nil)
    return try copyInto(baseURL, from: url)
  }

  private func copyInto(_ basePath: URL, from fromURL: URL) throws -> FBInstalledArtifact {
    let destination = basePath.appendingPathComponent(fromURL.lastPathComponent)
    logger.log("Persisting \(fromURL.lastPathComponent) to \(destination)")
    try FileManager.default.copyItem(at: fromURL, to: destination)
    logger.log("Persisted \(destination.lastPathComponent)")
    return FBInstalledArtifact(name: destination.lastPathComponent, uuid: nil, path: destination)
  }
}

// MARK: - FBBundleStorage

@objc public class FBBundleStorage: FBIDBStorage {
  @objc public let relocateLibraries: Bool

  @objc public init(target: FBiOSTarget, basePath: URL, queue: DispatchQueue, logger: FBControlCoreLogger, relocateLibraries: Bool) {
    self.relocateLibraries = relocateLibraries
    super.init(target: target, basePath: basePath, queue: queue, logger: logger)
  }

  @objc public func checkArchitecture(_ bundle: FBBundleDescriptor) throws {
    let binaryArchitectures = Set(bundle.binary!.architectures.map { $0.rawValue })
    let targetArchs = target.architectures
    let supportedArchitectures = Set(FBiOSTargetConfiguration.baseArchsToCompatibleArch(targetArchs).map { $0.rawValue })

    let containsExactArch = !binaryArchitectures.isDisjoint(with: supportedArchitectures)
    let arm64eEquivalent = targetArchs.contains(FBArchitecture(rawValue: "arm64e")) && binaryArchitectures.contains("arm64")

    if !(containsExactArch || arm64eEquivalent) {
      throw FBIDBError.describe("The supported architectures of the target \(FBCollectionInformation.oneLineDescription(from: supportedArchitectures.sorted())) do not intersect with any architectures in the bundle: \(FBCollectionInformation.oneLineDescription(from: binaryArchitectures.sorted()))").build()
    }
  }

  @objc public func saveBundle(_ bundle: FBBundleDescriptor) -> FBFuture<FBInstalledArtifact> {
    return saveBundle(bundle, usingSymlink: true, skipSigningBundles: false)
  }

  @objc public func saveBundle(_ bundle: FBBundleDescriptor, usingSymlink useSymlink: Bool, skipSigningBundles: Bool) -> FBFuture<FBInstalledArtifact> {
    do {
      try checkArchitecture(bundle)
    } catch {
      return FBFuture(error: error as NSError)
    }

    let storageDirectory = basePath.appendingPathComponent(bundle.identifier)
    do {
      try prepareDirectory(with: storageDirectory)
    } catch {
      return FBFuture(error: error as NSError)
    }

    let sourceBundlePath = URL(fileURLWithPath: bundle.path)
    let destinationBundlePath = storageDirectory.appendingPathComponent(sourceBundlePath.lastPathComponent)
    if useSymlink {
      logger.log("Symlink \(bundle.identifier) to \(destinationBundlePath)")
      do {
        try FileManager.default.createSymbolicLink(at: destinationBundlePath, withDestinationURL: sourceBundlePath)
      } catch {
        return FBFuture(error: error as NSError)
      }
    } else {
      logger.log("Moving \(bundle.identifier) to \(destinationBundlePath)")
      do {
        try FileManager.default.moveItem(at: sourceBundlePath, to: destinationBundlePath)
      } catch {
        return FBFuture(error: error as NSError)
      }
      logger.log("Moved \(bundle.identifier)")
    }

    let artifact = FBInstalledArtifact(name: bundle.identifier, uuid: bundle.binary?.uuid as NSUUID?, path: destinationBundlePath)
    if !relocateLibraries || !target.requiresBundlesToBeSigned() || skipSigningBundles {
      return FBFuture(result: artifact)
    }
    var updatedBundle: FBBundleDescriptor
    do {
      updatedBundle = try FBBundleDescriptor.bundle(fromPath: destinationBundlePath.path)
    } catch {
      return FBFuture(error: error as NSError)
    }
    let provider = FBCodesignProvider.codeSignCommand(withIdentityName: "-", logger: logger)
    return updatedBundle.updatePathsForRelocation(withCodesign: provider, logger: logger, queue: queue).mapReplace(artifact) as! FBFuture<FBInstalledArtifact>
  }

  @objc public var persistedBundleIDs: Set<String> {
    let contents = try? FileManager.default.contentsOfDirectory(atPath: basePath.path)
    return Set(contents ?? [])
  }

  @objc public var persistedBundles: [String: FBBundleDescriptor] {
    var mapping: [String: FBBundleDescriptor] = [:]
    guard let enumerator = FileManager.default.enumerator(at: basePath, includingPropertiesForKeys: nil, options: .skipsSubdirectoryDescendants, errorHandler: nil) else {
      return mapping
    }
    for case let directory as URL in enumerator {
      let key = directory.lastPathComponent
      guard let bundlePath = try? FBStorageUtils.findUniqueFile(inDirectory: directory) else {
        continue
      }
      do {
        let bundle = try FBBundleDescriptor.bundle(fromPath: bundlePath.path)
        mapping[key] = bundle
      } catch {
        logger.log("Failed to get bundle info for bundle at path \(bundlePath)")
      }
    }
    return mapping
  }

  @objc public override var replacementMapping: [String: String] {
    let bundles = persistedBundles
    var mapping: [String: String] = [:]
    for (_, bundle) in bundles {
      mapping[bundle.identifier] = bundle.path
      if let uuid = bundle.binary?.uuid {
        mapping[uuid.uuidString] = bundle.path
      }
    }
    return mapping
  }

  private func prepareDirectory(with url: URL) throws {
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
  }
}

// MARK: - FBXCTestBundleStorage

private let XctestExtension = "xctest"
private let XctestRunExtension = "xctestrun"

@objc public final class FBXCTestBundleStorage: FBBundleStorage {

  @objc public func saveBundleOrTestRunFromBaseDirectory(_ baseDirectory: URL, skipSigningBundles: Bool) -> FBFuture<FBInstalledArtifact> {
    let buckets: [String: Set<URL>]
    do {
      buckets = try FBStorageUtils.bucketFiles(withExtensions: Set([XctestExtension, XctestRunExtension]), inDirectory: baseDirectory)
    } catch {
      return FBFuture(error: error as NSError)
    }
    let xctestBucket = buckets[XctestExtension]?.sorted(by: { $0.path < $1.path }) ?? []
    let xctestBundleURL = xctestBucket.first
    if xctestBucket.count > 1 {
      return FBControlCoreError.describe("Multiple files with .xctest extension: \(FBCollectionInformation.oneLineDescription(from: xctestBucket))").failFuture() as! FBFuture<FBInstalledArtifact>
    }
    let xctestrunBucket = buckets[XctestRunExtension]?.sorted(by: { $0.path < $1.path }) ?? []
    let xctestrunURL = xctestrunBucket.first
    if xctestrunBucket.count > 1 {
      return FBControlCoreError.describe("Multiple files with .xctestrun extension: \(FBCollectionInformation.oneLineDescription(from: xctestrunBucket))").failFuture() as! FBFuture<FBInstalledArtifact>
    }
    if xctestBundleURL == nil && xctestrunURL == nil {
      return FBIDBError.describe("Neither a .xctest bundle or .xctestrun file provided: \(FBCollectionInformation.oneLineDescription(from: buckets))").failFuture() as! FBFuture<FBInstalledArtifact>
    }

    if let xctestBundleURL {
      return saveTestBundle(xctestBundleURL, usingSymlink: false, skipSigningBundles: skipSigningBundles)
    }
    if let xctestrunURL {
      return saveTestRun(xctestrunURL)
    }
    return FBIDBError.describe(".xctest bundle (\(String(describing: xctestBundleURL))) or .xctestrun (\(String(describing: xctestrunURL))) file was not saved").failFuture() as! FBFuture<FBInstalledArtifact>
  }

  @objc public func saveBundleOrTestRun(_ filePath: URL, skipSigningBundles: Bool) -> FBFuture<FBInstalledArtifact> {
    if filePath.pathExtension == XctestExtension {
      return saveTestBundle(filePath, usingSymlink: true, skipSigningBundles: skipSigningBundles)
    }
    if filePath.pathExtension == XctestRunExtension {
      return saveTestRun(filePath)
    }
    return FBControlCoreError.describe("The path extension (\(filePath.pathExtension)) of the provided bundle (\(filePath)) is not .xctest or .xctestrun").failFuture() as! FBFuture<FBInstalledArtifact>
  }

  @objc public func listTestDescriptors() throws -> [FBXCTestDescriptor] {
    var testDescriptors: [FBXCTestDescriptor] = []

    let testURLs = try listTestBundles()
    let xcTestRunURLs = try listXCTestRunFiles()

    for testURL in testURLs {
      do {
        let bundle = try FBBundleDescriptor.bundleWithFallbackIdentifier(fromPath: testURL.path)
        let testDescriptor = FBXCTestBootstrapDescriptor(url: testURL, name: bundle.name, testBundle: bundle)
        testDescriptors.append(testDescriptor)
      } catch {
        logger.error().log("\(error)")
      }
    }

    for xcTestRunURL in xcTestRunURLs {
      do {
        let descriptors = try getXCTestRunDescriptors(from: xcTestRunURL)
        testDescriptors.append(contentsOf: descriptors)
      } catch {
        logger.error().log("\(error)")
      }
    }

    return testDescriptors
  }

  @objc public func testDescriptor(withID bundleId: String) throws -> FBXCTestDescriptor {
    let testDescriptors = try listTestDescriptors()
    for testDescriptor in testDescriptors {
      if testDescriptor.testBundleID == bundleId {
        return testDescriptor
      }
    }
    throw FBIDBError.describe("Couldn't find test with id: \(bundleId)").build()
  }

  @objc public func getXCTestRunDescriptors(from xctestrunURL: URL) throws -> [FBXCTestDescriptor] {
    let contentDict = try FBXCTestRunFileReader.readContents(of: xctestrunURL, expandPlaceholderWithPath: target.auxillaryDirectory)
    let xctestrunMetadata = contentDict["__xctestrun_metadata__"] as? [String: NSNumber]
    if let xctestrunMetadata {
      logger.info().log("Using xctestrun format version: \(xctestrunMetadata["FormatVersion"] ?? 0)")
      return getDescriptors(from: contentDict, with: xctestrunURL)
    } else {
      logger.info().log("Using the legacy xctestrun file format")
      return legacyGetDescriptors(from: contentDict, with: xctestrunURL)
    }
  }

  // MARK: - Private

  private func listTestBundles() throws -> Set<URL> {
    return try listXCTestContents(withExtension: XctestExtension)
  }

  private func listXCTestRunFiles() throws -> Set<URL> {
    return try listXCTestContents(withExtension: XctestRunExtension)
  }

  private func xctestBundle(withID bundleID: String) throws -> URL {
    let directory = basePath.appendingPathComponent(bundleID)
    return try FBStorageUtils.findFile(withExtension: XctestExtension, at: directory)
  }

  private func listXCTestContents(withExtension ext: String) throws -> Set<URL> {
    guard let directories = try? FileManager.default.contentsOfDirectory(at: basePath, includingPropertiesForKeys: nil, options: .skipsSubdirectoryDescendants) else {
      throw FBIDBError.describe("Error reading test bundle base directory").build()
    }

    var tests = Set<URL>()
    for innerDirectory in directories {
      if let bundleURL = try? FBStorageUtils.findFile(withExtension: ext, at: innerDirectory) {
        tests.insert(bundleURL)
      }
    }
    return tests
  }

  private func testDescriptor(with url: URL) throws -> FBXCTestDescriptor {
    let testDescriptors = try listTestDescriptors()
    for testDescriptor in testDescriptors {
      if testDescriptor.url.absoluteString == url.absoluteString {
        return testDescriptor
      }
    }
    throw FBIDBError.describe("Couldn't find test with url: \(url)").build()
  }

  private func getDescriptors(from xctestrunContents: [String: Any], with xctestrunURL: URL) -> [FBXCTestDescriptor] {
    var descriptors: [FBXCTestDescriptor] = []
    for field in xctestrunContents.keys {
      logger.info().log("Checking the \(field) field to extract test descriptors")
      if field == "__xctestrun_metadata__" || field == "CodeCoverageBuildableInfos" {
        continue
      }
      if let descriptor = getDescriptor(for: field, from: xctestrunContents, with: xctestrunURL) {
        descriptors.append(descriptor)
      }
    }
    return descriptors
  }

  private func legacyGetDescriptors(from xctestrunContents: [String: Any], with xctestrunURL: URL) -> [FBXCTestDescriptor] {
    var descriptors: [FBXCTestDescriptor] = []
    for testTarget in xctestrunContents.keys {
      if let descriptor = getDescriptor(for: testTarget, from: xctestrunContents, with: xctestrunURL) {
        descriptors.append(descriptor)
      }
    }
    return descriptors
  }

  private func getDescriptor(for testTarget: String, from xctestrunContents: [String: Any], with xctestrunURL: URL) -> FBXCTestDescriptor? {
    guard let testTargetProperties = xctestrunContents[testTarget] as? [String: Any] else {
      return nil
    }
    let useArtifacts = testTargetProperties["UseDestinationArtifacts"] as? NSNumber
    if let useArtifacts, useArtifacts.boolValue {
      guard let hostIdentifier = testTargetProperties["TestHostBundleIdentifier"] as? String else {
        logger.error().log("Using UseDestinationArtifacts requires TestHostBundleIdentifier")
        return nil
      }
      guard let testIdentifier = testTargetProperties["FB_TestBundleIdentifier"] as? String else {
        logger.error().log("Using UseDestinationArtifacts requires FB_TestBundleIdentifier")
        return nil
      }
      let testBundle = FBBundleDescriptor(name: testIdentifier, identifier: testIdentifier, path: "", binary: nil)
      let hostBundle = FBBundleDescriptor(name: hostIdentifier, identifier: hostIdentifier, path: "", binary: nil)
      return FBXCodebuildTestRunDescriptor(url: xctestrunURL, name: testTarget, testBundle: testBundle, testHostBundle: hostBundle)
    }
    guard let testHostPath = testTargetProperties["TestHostPath"] as? String,
      let testBundlePath = testTargetProperties["TestBundlePath"] as? String
    else {
      return nil
    }
    guard let testHostBundle = try? FBBundleDescriptor.bundle(fromPath: testHostPath) else {
      return nil
    }
    guard let testBundle = try? FBBundleDescriptor.bundle(fromPath: testBundlePath) else {
      return nil
    }
    return FBXCodebuildTestRunDescriptor(url: xctestrunURL, name: testTarget, testBundle: testBundle, testHostBundle: testHostBundle)
  }

  private func saveTestBundle(_ testBundleURL: URL, usingSymlink useSymlink: Bool, skipSigningBundles: Bool) -> FBFuture<FBInstalledArtifact> {
    do {
      let bundle = try FBBundleDescriptor.bundleWithFallbackIdentifier(fromPath: testBundleURL.path)
      return saveBundle(bundle, usingSymlink: useSymlink, skipSigningBundles: skipSigningBundles)
    } catch {
      return FBFuture(error: error as NSError)
    }
  }

  private func saveTestRun(_ xcTestRunURL: URL) -> FBFuture<FBInstalledArtifact> {
    do {
      let descriptors = try getXCTestRunDescriptors(from: xcTestRunURL)
      if descriptors.count != 1 {
        return FBIDBError.describe("Expected exactly one test in the xctestrun file, got: \(descriptors.count)").failFuture() as! FBFuture<FBInstalledArtifact>
      }

      let descriptor = descriptors[0]
      if let toDelete = try? testDescriptor(withID: descriptor.testBundleID) {
        try FileManager.default.removeItem(at: toDelete.url.deletingLastPathComponent())
      }

      let uuidString = NSUUID().uuidString
      let newPath = basePath.appendingPathComponent(uuidString)
      try prepareDirectory(with: newPath)

      let dir = xcTestRunURL.deletingLastPathComponent()
      let contents = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [])
      for url in contents {
        try FileManager.default.copyItem(at: url, to: newPath.appendingPathComponent(url.lastPathComponent))
      }

      let artifact = FBInstalledArtifact(name: descriptor.testBundleID, uuid: nil, path: dir)
      return FBFuture(result: artifact)
    } catch {
      return FBFuture(error: error as NSError)
    }
  }

  private func prepareDirectory(with url: URL) throws {
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
  }
}

// MARK: - FBIDBStorageManager

@objc public final class FBIDBStorageManager: NSObject {
  @objc public let xctest: FBXCTestBundleStorage
  @objc public let application: FBBundleStorage
  @objc public let dylib: FBFileStorage
  @objc public let dsym: FBFileStorage
  @objc public let framework: FBBundleStorage
  @objc public let logger: FBControlCoreLogger

  private init(xctest: FBXCTestBundleStorage, application: FBBundleStorage, dylib: FBFileStorage, dsym: FBFileStorage, framework: FBBundleStorage, logger: FBControlCoreLogger) {
    self.xctest = xctest
    self.application = application
    self.dylib = dylib
    self.dsym = dsym
    self.framework = framework
    self.logger = logger
    super.init()
  }

  @objc public static func manager(forTarget target: FBiOSTarget, logger: FBControlCoreLogger) throws -> FBIDBStorageManager {
    let queue = DispatchQueue(label: "com.facebook.idb.bundle_storage")

    let xctestBasePath = try prepareStoragePath(withName: IdbTestBundlesFolder, target: target)
    let xctest = FBXCTestBundleStorage(target: target, basePath: xctestBasePath, queue: queue, logger: logger, relocateLibraries: true)

    let appBasePath = try prepareStoragePath(withName: IdbApplicationsFolder, target: target)
    let application = FBBundleStorage(target: target, basePath: appBasePath, queue: queue, logger: logger, relocateLibraries: false)

    let dylibBasePath = try prepareStoragePath(withName: IdbDylibsFolder, target: target)
    let dylib = FBFileStorage(target: target, basePath: dylibBasePath, queue: queue, logger: logger)

    let dsymBasePath = try prepareStoragePath(withName: IdbDsymsFolder, target: target)
    let dsym = FBFileStorage(target: target, basePath: dsymBasePath, queue: queue, logger: logger)

    let frameworkBasePath = try prepareStoragePath(withName: IdbFrameworksFolder, target: target)
    let framework = FBBundleStorage(target: target, basePath: frameworkBasePath, queue: queue, logger: logger, relocateLibraries: true)

    return FBIDBStorageManager(xctest: xctest, application: application, dylib: dylib, dsym: dsym, framework: framework, logger: logger)
  }

  @objc public func clean() throws {
    try xctest.clean()
    try application.clean()
    try dylib.clean()
    try dsym.clean()
    try framework.clean()
  }

  @objc public func interpolateArgumentReplacements(_ arguments: [String]?) -> [String] {
    guard let arguments else { return [] }
    logger.log("Original arguments: \(arguments)")
    let nameToPath = replacementMapping
    logger.log("Existing replacement mapping: \(nameToPath)")
    let interpolatedArguments = arguments.map { argument -> String in
      nameToPath[argument] ?? argument
    }
    logger.log("Interpolated arguments: \(interpolatedArguments)")
    return interpolatedArguments
  }

  @objc public var replacementMapping: [String: String] {
    var combined: [String: String] = [:]
    for mapping in [application.replacementMapping, dylib.replacementMapping, framework.replacementMapping, dsym.replacementMapping] {
      combined.merge(mapping) { _, new in new }
    }
    return combined
  }

  private static func prepareStoragePath(withName name: String, target: FBiOSTarget) throws -> URL {
    let basePath = URL(fileURLWithPath: target.auxillaryDirectory).appendingPathComponent(name)
    do {
      try FileManager.default.createDirectory(at: basePath, withIntermediateDirectories: true, attributes: nil)
    } catch {
      throw FBIDBError.describe("Failed to create xctest storage location \(basePath)").caused(by: error as NSError).build()
    }
    return basePath
  }
}
