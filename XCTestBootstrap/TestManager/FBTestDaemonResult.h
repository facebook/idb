/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class XCTestBootstrapError;

NS_ASSUME_NONNULL_BEGIN

/**
 The Final Result of a FBTestDaemonConnection.
 */
@interface FBTestDaemonResult : NSObject

/**
 A Successful Result.
 */
+ (instancetype)success;

/**
 A Client requested a disconnect.
 */
+ (instancetype)clientRequestedDisconnect;

/**
 A Failure Result.
 */
+ (instancetype)failedInError:(XCTestBootstrapError *)error;

/**
 YES if the Test Manager finished successfully, NO otherwise.
 */
@property (nonatomic, assign, readonly) BOOL didEndSuccessfully;

/**
 The Underlying error.
 */
@property (nonatomic, strong, nullable, readonly) NSError *error;

@end

NS_ASSUME_NONNULL_END
