/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

@class FBCrashLogInfo;

/**
 An interface for being notified of crash logs for a given process identifier.
 */
@interface FBCrashLogNotifier : NSObject

#pragma mark Notifications

/**
 Starts listening for crash logs.
 */
+ (void)startListening;

/**
 Obtains the next crash log, for a given process identifier.

 @param processIdentifier the process identifier of the process.
 @return a Future wrapping the crash log.
 */
+ (FBFuture<FBCrashLogInfo *> *)nextCrashLogForProcessIdentifier:(pid_t)processIdentifier;

@end

NS_ASSUME_NONNULL_END
