/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import IDBGRPCSwift

struct FileContainerValueTransformer {

  static func rawFileContainer(from proto: Idb_FileContainer) -> String {
    return fileContainer(from: proto.kind)?.rawValue ?? proto.bundleID
  }

  static func fileContainer(from proto: Idb_FileContainer.Kind) -> FBFileContainerKind? {
    switch proto {
    case .root:
      return .root
    case .media:
      return .media
    case .crashes:
      return .crashes
    case .provisioningProfiles:
      return .provisioningProfiles
    case .mdmProfiles:
      return .mdmProfiles
    case .springboardIcons:
      return .springboardIcons
    case .wallpaper:
      return .wallpaper
    case .diskImages:
      return .diskImages
    case .groupContainer:
      return .group
    case .applicationContainer:
      return .application
    case .auxillary:
      return .auxillary
    case .xctest:
      return .xctest
    case .dylib:
      return .dylib
    case .dsym:
      return .dsym
    case .framework:
      return .framework
    case .symbols:
      return .symbols
    case .application, .none, .UNRECOGNIZED:
      return nil
    }
  }
}
