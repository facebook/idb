/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "XCTestBootstrapError.h"

NSString *const XCTestBootstrapErrorDomain = @"com.facebook.XCTestBootstrap";

const NSInteger XCTestBootstrapErrorCodeStartupFailure = 0x3;
const NSInteger XCTestBootstrapErrorCodeLostConnection = 0x4;
const NSInteger XCTestBootstrapErrorCodeStartupTimeout = 0x5;

NSString *const FBTestErrorDomain = @"com.facebook.FBTestError";
