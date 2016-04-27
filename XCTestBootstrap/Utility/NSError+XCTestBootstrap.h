/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

/**
 Error Codes for XCTestBootstrap Errors.
 */
typedef NS_ENUM(NSUInteger, XCTestBootstrapErrorCode) {
  XCTestBootstrapErrorCodeGeneral,
};

/**
 The Error Domain for XCTestBootstrap Errors.
 */
extern NSString *const XCTestBootstrapErrorDomain;

/**
 XCTestBootstrap Errors construction.
 */
@interface NSError (XCTestBootstrap)

/**
 Creates and returns a new Error with the provided description.

 @param description the description for the error.
 @return a new NSError.
 */
+ (instancetype)XCTestBootstrapErrorWithDescription:(NSString *)description;

@end
