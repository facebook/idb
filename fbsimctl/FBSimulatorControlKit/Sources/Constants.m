/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "Constants.h"

#import <sys/socket.h>

@implementation Constants

+ (int32_t)sol_socket
{
  return SOL_SOCKET;
}

+ (int32_t)so_reuseaddr
{
  return SO_REUSEADDR;
}

@end
