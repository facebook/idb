/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// FBTestConfiguration.h only forward-declares XCTestConfiguration; Swift cannot
// see members typed with forward-declared classes, so the tests need the real
// declaration in view.
#import "XCTestPrivate/XCTestConfiguration.h"
