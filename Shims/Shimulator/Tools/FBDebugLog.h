/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

/*
 Logs shims debug messages in case SHIMULATOR_DEBUG is set
*/
void FBDebugLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
