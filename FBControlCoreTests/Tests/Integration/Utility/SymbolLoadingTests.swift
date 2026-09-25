/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import Testing

/// Pins symbol resolution against the framework the production callers use it on: MobileDevice,
/// loaded through `WeakFramework` exactly as `DeviceControlFrameworkLoader` loads it, then opened
/// and searched for one of the `AMDevice` symbols that loader resolves.
///
/// An integration test rather than a unit one: `dlopenExecutablePath` asserts on a bundle NSBundle
/// does not consider loaded, so the bundle has to be loaded for real first. A shared-cache
/// framework such as Foundation reports `isLoaded == false` and trips that assertion.
@Suite("Dynamic symbol loading")
struct SymbolLoadingTests {

  private static let resolvableSymbol = "AMDeviceConnect"

  private static func mobileDeviceHandle() throws -> UnsafeMutableRawPointer {
    try WeakFramework.mobileDevice.load(with: nil)
    let bundle = try #require(Bundle(identifier: "com.apple.mobiledevice"))

    return bundle.dlopenExecutablePath()
  }

  @Test("A loaded bundle's executable opens and resolves one of its own symbols")
  func opensALoadedBundleAndResolvesItsSymbols() throws {
    let handle = try Self.mobileDeviceHandle()

    #expect(FBGetSymbolFromHandleOptional(handle, Self.resolvableSymbol) != nil)
  }

  @Test("A name that does not resolve is reported as nil rather than as an address")
  func unresolvableNameIsReportedAsNil() throws {
    let handle = try Self.mobileDeviceHandle()

    #expect(FBGetSymbolFromHandleOptional(handle, "IDBNotASymbolInMobileDevice") == nil)
  }

  @Test("Both resolution forms agree on the address of a symbol that exists")
  func bothFormsResolveTheSameAddress() throws {
    let handle = try Self.mobileDeviceHandle()
    let optional = try #require(FBGetSymbolFromHandleOptional(handle, Self.resolvableSymbol))

    #expect(FBGetSymbolFromHandle(handle, Self.resolvableSymbol) == optional)
  }

  @Test("Opening the same bundle twice hands back the same image")
  func repeatedOpensResolveTheSameImage() throws {
    let first = try Self.mobileDeviceHandle()
    let second = try Self.mobileDeviceHandle()

    #expect(
      FBGetSymbolFromHandleOptional(first, Self.resolvableSymbol)
        == FBGetSymbolFromHandleOptional(second, Self.resolvableSymbol))
  }
}
