/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBiOSTargetCommandForwarder.h>

@class FBInstrumentsConfiguration;
@class FBInstrumentsOperation;

/**
 Defines an interface for interacting with Instruments.
 */
@protocol FBInstrumentsCommandsProtocol <NSObject, FBiOSTargetCommand>

/**
 Runs instruments with the given configuration

 @param configuration the configuration to use.
 @param logger the logger to use.
 @return A future that resolves with the instruments operation.
 */
- (nonnull FBFuture<FBInstrumentsOperation *> *)startInstruments:(nonnull FBInstrumentsConfiguration *)configuration logger:(nonnull id<FBControlCoreLogger>)logger;

@end

/**
 A concrete implementation of FBInstrumentsCommandsProtocol.
 */
@interface FBInstrumentsCommands : NSObject <FBInstrumentsCommandsProtocol>

@property (nonnull, nonatomic, readonly, strong) id<FBiOSTarget> target;

@end
