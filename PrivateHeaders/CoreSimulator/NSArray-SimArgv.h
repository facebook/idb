/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/NSArray.h>

@interface NSArray (SimArgv)
- (void)sim_freeArgv:(char **)arg1;
@property (readonly, nonatomic) char **sim_argv;
@end
