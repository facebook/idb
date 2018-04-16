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
#import <FBControlCore/FBiOSTargetCommandForwarder.h>
#import <FBControlCore/FBiOSTargetFuture.h>

NS_ASSUME_NONNULL_BEGIN

@class FBCrashLogInfo;

/**
 Commands for obtaining crash logs.
 */
@protocol FBCrashLogCommands <NSObject, FBiOSTargetCommand>

/**
 Starts tailing the log of a Simulator to a consumer.

 @param processIdentifier the process identifier of the process.
 @return a Future that will complete when the log command has started successfully. The wrapped Awaitable can then be cancelled, or awaited until it is finished.
 */
- (FBFuture<FBCrashLogInfo *> *)notifyOfCrash:(pid_t)processIdentifier;

@end

/**
 An implementation of FBCrashLogCommands, that looks for crash logs on the host.
 */
@interface FBHostCrashLogCommands : NSObject <FBCrashLogCommands>

@end

NS_ASSUME_NONNULL_END

