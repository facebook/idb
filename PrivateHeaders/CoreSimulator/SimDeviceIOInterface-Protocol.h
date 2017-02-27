/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

@class NSString;

@protocol SimDeviceIOInterface
- (BOOL)unregisterService:(NSString *)arg1 error:(id *)arg2;
- (BOOL)registerPort:(unsigned int)arg1 service:(NSString *)arg2 error:(id *)arg3;
@end
