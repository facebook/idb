/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import SimulatorFrameworkBridgeSupport

// The fakes are Objective-C so they can stand in for private classes. The services under test are
// Swift, so each fake takes its service as a block and these supply it.

extension FBContactsTestRuntime {
  func run() -> Int {
    run { FBContactsService.clear(with: $0, makeSaveRequest: $1) }
  }
}

extension FBPhotosTestRuntime {
  func run() -> Int {
    run { FBPhotoLibraryService.clear(client: $0) }
  }

  func runCatchingException() -> [String: Any] {
    runCatchingException { FBPhotoLibraryService.clear(client: $0) }
  }
}

extension FBDynamicStoreTestRuntime {
  func run(action: String, arguments: [String], input: Data?) -> Int {
    run(input: input) { FBDynamicStoreService.handleDynamicStoreAction(action: action, arguments: arguments) }
  }
}

extension FBNetworkConfigurationTestRuntime {
  func run(service: String, action: String, arguments: [String]) -> Int {
    run {
      service == "dns"
        ? FBDnsService.handleDnsAction(action: action, arguments: arguments)
        : FBProxyService.handleProxyAction(action: action, arguments: arguments)
    }
  }
}

extension FBHealthTestRuntime {
  func runAction(_ action: String, bundleID: String?, types: [String]) -> [String: Any] {
    run { FBHealthSettingsService.handleHealthSettingsAction(action: action, bundleID: bundleID, typeIdentifiers: types) }
  }
}
