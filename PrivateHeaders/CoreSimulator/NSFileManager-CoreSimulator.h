/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/NSFileManager.h>

@interface NSFileManager (CoreSimulator)
- (BOOL)sim_copyItemAtPath:(id)arg1 toCreatedPath:(id)arg2 error:(id *)arg3;
- (BOOL)sim_reentrantSafeCreateDirectoryAtPath:(id)arg1 withIntermediateDirectories:(BOOL)arg2 attributes:(id)arg3 error:(id *)arg4;
@end
