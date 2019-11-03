/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/*
 Logs shims debug messages in case SHIMULATOR_DEBUG is set
*/
void FBDebugLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
