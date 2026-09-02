/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <FBDeviceControl/FBDeviceDebugSymbolsCommands.h>

#import "FBDeviceControlTestHelpers.h"

/**
 Implementation-private helpers of FBDeviceDebugSymbolsCommands, declared here rather than in the
 framework header so the test target can reach them without widening the public interface.
 These are the parts of the symbol service that need no connection: which of the remote files make
 up the shared cache, and how they map back to the indices the service addresses them by.
 */
@interface FBDeviceDebugSymbolsCommands (Testing)

+ (nonnull NSArray<NSString *> *)matchingPathsOfSharedCache:(nonnull NSArray<NSString *> *)files;
+ (nullable NSDictionary<NSNumber *, NSString *> *)matchFiles:(nonnull NSArray<NSString *> *)files againstFileIndices:(nonnull NSArray<NSString *> *)fileIndices error:(NSError *_Nullable *_Nullable)error;
+ (nullable NSString *)extractSharedCachePathFromPaths:(nonnull NSArray<NSString *> *)paths error:(NSError *_Nullable *_Nullable)error;

@end
