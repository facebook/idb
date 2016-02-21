/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBSimulatorControl.h>

/**
 Bridging Preprocessor Macros to values, so that they can be read in Swift.
 */
@interface Constants : NSObject

+ (int32_t)sol_socket;
+ (int32_t)so_reuseaddr;

+ (int32_t)asl_level_info;
+ (int32_t)asl_level_debug;
+ (int32_t)asl_level_err;

@end

@interface NSString (FBJSONSerializationDescribeable) <FBJSONSerializationDescribeable>
@end

@interface NSArray (FBJSONSerializationDescribeable) <FBJSONSerializationDescribeable>
@end
