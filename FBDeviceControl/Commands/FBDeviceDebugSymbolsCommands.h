/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBDevice;

/**
 An Implementation of FBDeviceDebugSymbolsCommands.
 */
@interface FBDeviceDebugSymbolsCommands : NSObject

- (nonnull instancetype)initWithDevice:(nonnull FBDevice *)device;
- (nonnull FBFuture<NSArray<NSString *> *> *)listSymbols;
- (nonnull FBFuture<NSString *> *)pullSymbolFile:(nonnull NSString *)fileName toDestinationPath:(nonnull NSString *)destinationPath;
- (nonnull FBFuture<NSString *> *)pullAndExtractSymbolsToDestinationDirectory:(nonnull NSString *)destinationDirectory;

@end
