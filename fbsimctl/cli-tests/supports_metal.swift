#!/usr/bin/env xcrun swift -F /usr/local/Frameworks
/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Metal

// Exits non-zero if Metal is supported by the OS version but not
// available on the current hardware. Is used in fbsimctl's
// e2e-tests to see if video recording can be tested or not.
if #available(OSX 10.11, *) {
  if MTLCreateSystemDefaultDevice() == nil {
    exit(1)
  }
}
