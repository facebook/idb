/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

/**
 The Error Domain for XCTestBootstrap Errors.
 */
extern NSString * _Nonnull const XCTestBootstrapErrorDomain;

/**
 Error Codes.
 */
extern const NSInteger XCTestBootstrapErrorCodeStartupFailure;
extern const NSInteger XCTestBootstrapErrorCodeLostConnection;
extern const NSInteger XCTestBootstrapErrorCodeStartupTimeout;

/**
 XCTestBootstrap Errors construction.
 */
@interface XCTestBootstrapError : FBControlCoreError

@end

/**
 The Error Domain for FBTestErrorDomain Errors.
 */
extern NSString * _Nonnull const FBTestErrorDomain;

/**
 FBXCTest Errors construction.
 */
@interface FBXCTestError : FBControlCoreError

@end
