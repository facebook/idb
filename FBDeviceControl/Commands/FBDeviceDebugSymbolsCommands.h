/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

#import <FBDeviceControl/FBDeviceCommands.h>

NS_ASSUME_NONNULL_BEGIN

@class FBDevice;

/**
 The Protocol for Debug Symbol related commands.
 */
@protocol FBDeviceDebugSymbolsCommands <FBiOSTargetCommand>

/**
 Obtains a listing of symbol files on a device.

 @return A future that resolves with the listing of symbol files..
 */
- (FBFuture<NSArray<NSString *> *> *)listSymbols;

/**
 Writes a file out to a destination

 @param fileName the file to pull
 @param destinationPath the destination to write to.
 @return a  Future that resolves with the extract path.
 */
- (FBFuture<NSString *> *)pullSymbolFile:(NSString *)fileName toDestinationPath:(NSString *)destinationPath;

/**
 Pulls and extracts symbols to the provided path.

 @param destinationDirectory the destination to write to.
 @return a  Future that resolves with the extract path.
 */
- (FBFuture<NSString *> *)pullAndExtractSymbolsToDestinationDirectory:(NSString *)destinationDirectory;

@end

/**
 An Implementation of FBDeviceDebugSymbolsCommands.
 */
@interface FBDeviceDebugSymbolsCommands : NSObject <FBDeviceDebugSymbolsCommands>

@end

NS_ASSUME_NONNULL_END
