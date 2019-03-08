/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/NSDictionary.h>

@interface NSDictionary (SimEnvp)
- (void)sim_freeEnvp:(char **)arg1;
@property (readonly, nonatomic) char **sim_envp;
@end
