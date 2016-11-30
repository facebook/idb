/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;

/**
 Modifies a Plist on the Simulator.
 */
@interface FBPlistModificationStrategy : NSObject

/**
 A Strategy for modifying a plist.

 @param simulator the Simulator to use.
 @return a new strategy for the Simulator.
 */
+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator;

/**
 Amends a Plist, relative to a root path.

 @param relativePath the relative path from the Simulator root.
 @param error an error out for any error that occurs.
 @param block the block to use for modifications.
 @return YES if successful, NO otherwise.
 */
- (BOOL)amendRelativeToPath:(NSString *)relativePath error:(NSError **)error amendWithBlock:( void(^)(NSMutableDictionary<NSString *, id> *) )block;

@end

NS_ASSUME_NONNULL_END
