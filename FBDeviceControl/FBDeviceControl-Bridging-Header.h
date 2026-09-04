/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Static libraries have no umbrella header, so the target's own Objective-C surface reaches
// Swift through this bridging header.
#import "FBDeviceControl.h"
