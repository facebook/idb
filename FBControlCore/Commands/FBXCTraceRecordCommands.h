/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBiOSTargetCommandForwarder.h>
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

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
- (FBFuture<FBXCTraceRecordOperation *> *)startXctraceRecord:(FBXCTraceRecordConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger;

@end

/**
 A concrete implementation of FBXCTraceRecordCommands.
 */
@interface FBXCTraceRecordCommands : NSObject <FBXCTraceRecordCommands>

@property (nonatomic, weak, readonly) id<FBiOSTarget> target;

@end

NS_ASSUME_NONNULL_END
