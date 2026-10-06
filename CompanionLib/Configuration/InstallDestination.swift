/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore

/// What to install an artifact as, with the options only that kind takes.
public enum InstallDestination: Sendable {
  case application(makeDebuggable: Bool)
  case xctest(skipSigningBundles: Bool)
  case framework
  case dylib
  case dsym(linkTo: DsymInstallLinkToBundle?)

  var kind: ArtifactKind {
    switch self {
    case .application:
      return .application
    case .xctest:
      return .xctest
    case .framework:
      return .framework
    case .dylib:
      return .dylib
    case .dsym:
      return .dsym
    }
  }

  var makeDebuggable: Bool {
    guard case .application(let makeDebuggable) = self else {
      return false
    }
    return makeDebuggable
  }

  var skipSigningBundles: Bool {
    guard case .xctest(let skipSigningBundles) = self else {
      return false
    }
    return skipSigningBundles
  }

  var linkTo: DsymInstallLinkToBundle? {
    guard case .dsym(let linkTo) = self else {
      return nil
    }
    return linkTo
  }
}
