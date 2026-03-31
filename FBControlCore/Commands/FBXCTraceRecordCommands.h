/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBiOSTargetCommandForwarder.h>

@class FBXCTraceRecordConfiguration;
@class FBXCTraceRecordOperation;

/**
 Defines an interface for running `xctrace record`.
 */
@protocol FBXCTraceRecordCommands <NSObject, FBiOSTargetCommand>

/**
 Run `xctrace record` with the given configuration

 @param configuration the configuration to use.
 @param logger the logger to use.
 @return A future that resolves with the `xctrace record` operation.
 */
- (nonnull FBFuture<FBXCTraceRecordOperation *> *)startXctraceRecord:(nonnull FBXCTraceRecordConfiguration *)configuration logger:(nonnull id<FBControlCoreLogger>)logger;

@end

/**
 A concrete implementation of FBXCTraceRecordCommands.
 */
@interface FBXCTraceRecordCommands : NSObject <FBXCTraceRecordCommands>

@property (nonnull, nonatomic, readonly, strong) id<FBiOSTarget> target;

@end
