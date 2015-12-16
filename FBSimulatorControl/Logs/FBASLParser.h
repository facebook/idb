/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBWritableLog;
@class FBProcessInfo;

/**
 Reads ASL Messages using asl(3).
 */
@interface FBASLParser : NSObject

/**
 Creates and returns a new ASL Parser.
 */
+ (instancetype)parserForPath:(NSString *)path;

/**
 Returns a FBWritableLog for the log messages relevant to the provided process info.
 
 @param processInfo the Process Info to obtain filtered log information.
 */
- (FBWritableLog *)writableLogForProcessInfo:(FBProcessInfo *)processInfo;

@end
