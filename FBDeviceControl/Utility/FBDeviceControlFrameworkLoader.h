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
 Loads Frameworks that FBDeviceControl depends on.
 */
@interface FBDeviceControlFrameworkLoader : NSObject

/**
 Loads the Relevant Private Frameworks for ensuring the essential operation of FBDeviceControl.
 */
+ (void)initializeEssentialFrameworks;

/**
 Loads the Relevant Private Frameworks for ensuring the essential operation of FBDeviceControl.
 */
+ (void)initializeXCodeFrameworks;

@end
