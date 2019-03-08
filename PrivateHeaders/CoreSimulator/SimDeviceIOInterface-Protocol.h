/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@class NSString;

@protocol SimDeviceIOInterface
- (BOOL)unregisterService:(NSString *)arg1 error:(id *)arg2;
- (BOOL)registerPort:(unsigned int)arg1 service:(NSString *)arg2 error:(id *)arg3;
@end
