/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBDevice;
@protocol FBDeviceDebugSymbolsCommandsProtocol;

/**
 An Implementation of FBDeviceDebugSymbolsCommands.
 */
@interface FBDeviceDebugSymbolsCommands : NSObject

// Initializer and protocol methods declared explicitly so Swift can see them
// on the concrete class. Conformance to the Swift-defined
// FBDeviceDebugSymbolsCommandsProtocol is structural — the class implements
// every method the protocol requires.
- (nonnull instancetype)initWithDevice:(nonnull FBDevice *)device;
- (nonnull FBFuture<NSArray<NSString *> *> *)listSymbols;
- (nonnull FBFuture<NSString *> *)pullSymbolFile:(nonnull NSString *)fileName toDestinationPath:(nonnull NSString *)destinationPath;
- (nonnull FBFuture<NSString *> *)pullAndExtractSymbolsToDestinationDirectory:(nonnull NSString *)destinationDirectory;

@end
