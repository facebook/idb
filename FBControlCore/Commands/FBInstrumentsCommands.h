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

@protocol FBInstrumentsCommandsProtocol;

/**
 A concrete implementation of FBInstrumentsCommandsProtocol.
 Protocol conformance is declared in Swift (FBInstrumentsCommands.swift).
 */
// @lint-ignore FBOBJCDEPRECATEDCHECK
@interface FBInstrumentsCommands : NSObject

@property (nonnull, nonatomic, readonly, strong) id<FBiOSTarget> target;

+ (nonnull instancetype)commandsWithTarget:(nonnull id<FBiOSTarget>)target;
- (nonnull FBFuture<FBInstrumentsOperation *> *)startInstruments:(nonnull FBInstrumentsConfiguration *)configuration logger:(nonnull id<FBControlCoreLogger>)logger;

@end
