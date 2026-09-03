/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Static libraries have no umbrella header for the Swift compiler to use, so
// the target's own Objective-C surface is exposed to Swift through this
// bridging header (the .framework product did this implicitly).
#import "FBDeviceControl.h"
