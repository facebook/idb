/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBDeviceCommands.h>

@class FBDevice;

/**
 The Protocol for Debug Symbol related commands.
 */
@protocol FBDeviceDebugSymbolsCommandsProtocol <FBiOSTargetCommand>

/**
 Obtains a listing of symbol files on a device.

 @return A future that resolves with the listing of symbol files..
 */
- (nonnull FBFuture<NSArray<NSString *> *> *)listSymbols;

/**
 Writes a file out to a destination

 @param fileName the file to pull
 @param destinationPath the destination to write to.
 @return a  Future that resolves with the extract path.
 */
- (nonnull FBFuture<NSString *> *)pullSymbolFile:(nonnull NSString *)fileName toDestinationPath:(nonnull NSString *)destinationPath;

/**
 Pulls and extracts symbols to the provided path.

 @param destinationDirectory the destination to write to.
 @return a  Future that resolves with the extract path.
 */
- (nonnull FBFuture<NSString *> *)pullAndExtractSymbolsToDestinationDirectory:(nonnull NSString *)destinationDirectory;

@end

/**
 An Implementation of FBDeviceDebugSymbolsCommands.
 */
@interface FBDeviceDebugSymbolsCommands : NSObject <FBDeviceDebugSymbolsCommandsProtocol>

@end
