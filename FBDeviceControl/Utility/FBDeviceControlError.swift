/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBDeviceControlError)
open class FBDeviceControlError: FBControlCoreError {

  public required init() {
    super.init()
    inDomain(FBDeviceControlErrorDomain)
  }
}
