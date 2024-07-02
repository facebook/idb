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

@class FBInstrumentsConfiguration;
@class FBInstrumentsOperation;

/**
 Defines an interface for interacting with Instruments.
 */
@protocol FBInstrumentsCommands <NSObject, FBiOSTargetCommand>

/**
 Runs instruments with the given configuration

 @param configuration the configuration to use.
 @param logger the logger to use.
 @return A future that resolves with the instruments operation.
 */
- (FBFuture<FBInstrumentsOperation *> *)startInstruments:(FBInstrumentsConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger;

@end

/**
 A concrete implementation of FBInstrumentsCommands.
 */
@interface FBInstrumentsCommands : NSObject <FBInstrumentsCommands>

@property (nonatomic, weak, readonly) id<FBiOSTarget> target;

@end

NS_ASSUME_NONNULL_END
