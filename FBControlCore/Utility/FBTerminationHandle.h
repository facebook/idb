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
 Extensible Diagnostic Name Enumeration.
 */
typedef NSString *FBTerminationHandleType NS_EXTENSIBLE_STRING_ENUM;

/**
 Simple protocol that allows asynchronous operations to be terminated.
 */
@protocol FBTerminationHandle <NSObject>

/**
 Terminates the asynchronous operation.
 */
- (void)terminate;

/**
 The Type of Termination Handle.
 */
- (FBTerminationHandleType)type;

@end
