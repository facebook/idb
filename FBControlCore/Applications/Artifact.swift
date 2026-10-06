/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

enum ArtifactError: Error {
  case multipleXctestFiles(files: [URL])
  case multipleXctestrunFiles(files: [URL])
  case noTestArtifactsProvided(bucketsDescription: String)
  case invalidPathExtension(pathExtension: String, path: URL)
}

extension ArtifactError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .multipleXctestFiles(files):
      return "Multiple files with .xctest extension: \(CollectionInformation.oneLineDescription(from: files))"
    case let .multipleXctestrunFiles(files):
      return "Multiple files with .xctestrun extension: \(CollectionInformation.oneLineDescription(from: files))"
    case let .noTestArtifactsProvided(bucketsDescription):
      return "Neither a .xctest bundle or .xctestrun file provided: \(bucketsDescription)"
    case let .invalidPathExtension(pathExtension, path):
      return "The path extension (\(pathExtension)) of the provided bundle (\(path)) is not .xctest or .xctestrun"
    }
  }
}

/// What a staged install source holds, found without touching storage or the target.
public enum Artifact {
  case application(BundleDescriptor)
  case testBundle(URL)
  case testRun(URL)
  case framework(BundleDescriptor)
  case dylib(URL)
  case dsym(URL)
}

// MARK: - Applications

extension Artifact {

  /// Where the artifact is on disk.
  public var url: URL {
    switch self {
    case .application(let bundle), .framework(let bundle):
      return URL(fileURLWithPath: bundle.path)
    case .testBundle(let url), .testRun(let url), .dylib(let url), .dsym(let url):
      return url
    }
  }

  /// The application bundle in `tree`, which is the item itself if it is in place, or else the first `.app` found in
  /// what was staged.
  public static func applicationBundle(in tree: StagedTree, logger: (any ControlCoreLogger)? = nil) throws -> BundleDescriptor {
    let directory: URL
    switch tree {
    case .inPlace(let bundle):
      return try BundleDescriptor.bundle(fromPath: bundle.path)
    case .extracted(let extracted):
      directory = extracted
    case .file(let file):
      directory = file.deletingLastPathComponent()
    }
    do {
      return try BundleDescriptor.findAppPath(fromDirectory: directory, logger: logger)
    } catch {
      throw InstallError.noInstallableBundle(inDirectory: directory.path, underlying: error)
    }
  }
}

/// The kind of artifact a client asked to install.
public enum ArtifactKind: Sendable {
  case application
  case xctest
  case framework
  case dylib
  case dsym

  /// Finds the artifact of this kind in `tree`.
  ///
  /// An item left in place is the artifact itself. Anything staged is searched for it: an archive's extraction directory, or
  /// the directory holding a decompressed file.
  public func identify(in tree: StagedTree, logger: (any ControlCoreLogger)? = nil) throws -> Artifact {
    switch self {
    case .application:
      return .application(try Artifact.applicationBundle(in: tree, logger: logger))
    case .xctest:
      if case .inPlace(let item) = tree {
        return try Self.testArtifact(at: item)
      }
      return try Self.testArtifact(inDirectory: Self.directory(of: tree))
    case .framework:
      if case .inPlace(let item) = tree {
        return .framework(try BundleDescriptor.bundle(fromPath: item.path))
      }
      return .framework(try StorageUtils.bundle(inDirectory: Self.directory(of: tree)))
    case .dylib:
      switch tree {
      case .inPlace(let file), .file(let file):
        return .dylib(file)
      case .extracted(let directory):
        return .dylib(try StorageUtils.findUniqueFile(inDirectory: directory))
      }
    case .dsym:
      if case .inPlace(let item) = tree {
        return .dsym(item)
      }
      // A single item is the dSYM; several are stored together as the directory holding them.
      let directory = Self.directory(of: tree)
      let children = try StorageUtils.files(inDirectory: directory)
      return .dsym(children.count == 1 ? children[0] : directory)
    }
  }

  private static func directory(of tree: StagedTree) -> URL {
    switch tree {
    case .extracted(let directory), .inPlace(let directory):
      return directory
    case .file(let file):
      return file.deletingLastPathComponent()
    }
  }

  private static func testArtifact(at item: URL) throws -> Artifact {
    switch item.pathExtension {
    case XctestExtension:
      return .testBundle(item)
    case XctestRunExtension:
      return .testRun(item)
    default:
      throw ArtifactError.invalidPathExtension(pathExtension: item.pathExtension, path: item)
    }
  }

  private static func testArtifact(inDirectory directory: URL) throws -> Artifact {
    let buckets = try StorageUtils.bucketFiles(withExtensions: [XctestExtension, XctestRunExtension], inDirectory: directory)
    let bundles = buckets[XctestExtension]?.sorted(by: { $0.path < $1.path }) ?? []
    if bundles.count > 1 {
      throw ArtifactError.multipleXctestFiles(files: bundles)
    }
    let runs = buckets[XctestRunExtension]?.sorted(by: { $0.path < $1.path }) ?? []
    if runs.count > 1 {
      throw ArtifactError.multipleXctestrunFiles(files: runs)
    }
    if let bundle = bundles.first {
      return .testBundle(bundle)
    }
    if let run = runs.first {
      return .testRun(run)
    }
    throw ArtifactError.noTestArtifactsProvided(bucketsDescription: CollectionInformation.oneLineDescription(from: buckets))
  }
}

private let XctestExtension = "xctest"
private let XctestRunExtension = "xctestrun"
