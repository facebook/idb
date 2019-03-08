/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/NSError.h>

@interface NSError (SimError)
+ (id)errorWithSimPairingTestResult:(long long)arg1;
+ (id)errorWithLaunchdError:(int)arg1 userInfo:(id)arg2;
+ (id)errorWithLaunchdError:(int)arg1 localizedDescription:(id)arg2;
+ (id)errorWithLaunchdError:(int)arg1;
+ (id)errorWithSimErrno:(int)arg1 localizedDescription:(id)arg2;
+ (id)errorWithSimErrno:(int)arg1 userInfo:(id)arg2;
+ (id)errorWithSimErrno:(int)arg1;
@end

