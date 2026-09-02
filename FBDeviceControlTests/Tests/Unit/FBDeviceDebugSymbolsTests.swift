/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBDeviceControl
import Foundation
import Testing

/// A listing shaped like the one `com.apple.dt.fetchsymbols` returns: the shared cache and its
/// sidecar files, surrounded by entries that must not be mistaken for them.
private let remoteListing = [
  "/private/var/db/stash/shared_cache_decoy",
  "/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64e",
  "/System/Library/CoreServices/SystemVersion.plist",
  "/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64e.symbols",
  "/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64e.map",
]

/// The service addresses files by their position in the listing, so the mapping is asserted
/// against indices into `remoteListing` rather than literals.
private func index(of path: String) -> Int {
  guard let index = remoteListing.firstIndex(of: path) else {
    preconditionFailure("\(path) is not part of the listing under test")
  }
  return index
}

private func indexedByPosition(_ matched: [NSNumber: String]) -> [Int: String] {
  Dictionary(uniqueKeysWithValues: matched.map { (Int(truncating: $0.key), $0.value) })
}

@Suite
struct FBDeviceDebugSymbolsTests {

  // MARK: - Selecting the shared cache files

  @Test
  func selectsOnlySharedCacheFilesUnderSystemLibrary() {
    let matching = FBDeviceDebugSymbolsCommands.matchingPathsOfSharedCache(remoteListing)

    #expect(
      matching == [
        "/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64e",
        "/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64e.symbols",
        "/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64e.map",
      ])
  }

  @Test
  func excludesSharedCacheNamesOutsideSystemLibrary() {
    let matching = FBDeviceDebugSymbolsCommands.matchingPathsOfSharedCache([
      "/private/var/db/stash/shared_cache_decoy"
    ])

    #expect(matching == [])
  }

  @Test
  func excludesSystemLibraryFilesThatAreNotSharedCache() {
    let matching = FBDeviceDebugSymbolsCommands.matchingPathsOfSharedCache([
      "/System/Library/CoreServices/SystemVersion.plist"
    ])

    #expect(matching == [])
  }

  // MARK: - Mapping files back to their indices

  @Test
  func mapsEachFileToItsPositionInTheListing() throws {
    let cache = "/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64e"
    let map = "/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64e.map"

    let matched = try FBDeviceDebugSymbolsCommands.matchFiles([cache, map], againstFileIndices: remoteListing)

    #expect(indexedByPosition(matched) == [index(of: cache): cache, index(of: map): map])
  }

  @Test
  func failsWhenAFileIsAbsentFromTheListing() {
    let error = #expect(throws: (any Error).self) {
      try FBDeviceDebugSymbolsCommands.matchFiles(["/System/Library/Caches/absent"], againstFileIndices: remoteListing)
    }

    #expect(
      (error as? NSError)?.localizedDescription
        == "Could not find /System/Library/Caches/absent within \(FBCollectionInformation.oneLineDescription(from: remoteListing))")
  }

  // MARK: - Picking the cache out of the pulled files

  @Test
  func takesTheExtensionlessFileAsTheSharedCache() throws {
    let paths = [
      "/local/dyld_shared_cache_arm64e.symbols",
      "/local/dyld_shared_cache_arm64e",
      "/local/dyld_shared_cache_arm64e.map",
    ]

    let sharedCache = try FBDeviceDebugSymbolsCommands.extractSharedCachePath(fromPaths: paths)

    #expect(sharedCache == "/local/dyld_shared_cache_arm64e")
  }

  @Test
  func failsWhenEveryPulledFileHasAnExtension() {
    let paths = ["/local/dyld_shared_cache_arm64e.symbols", "/local/dyld_shared_cache_arm64e.map"]

    let error = #expect(throws: (any Error).self) {
      try FBDeviceDebugSymbolsCommands.extractSharedCachePath(fromPaths: paths)
    }

    #expect(
      (error as? NSError)?.localizedDescription
        == "Could not find the shared cache file within \(FBCollectionInformation.oneLineDescription(from: paths))")
  }
}
