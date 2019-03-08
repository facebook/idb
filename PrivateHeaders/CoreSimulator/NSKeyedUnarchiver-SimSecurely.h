/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/NSKeyedUnarchiver.h>

@interface NSKeyedUnarchiver (SimSecurely)
+ (id)sim_securelyUnarchiveObjectWithClasses:(id)arg1 data:(id)arg2;
+ (id)sim_securelyUnarchiveObjectWithData:(id)arg1;
+ (void)sim_securelyWhitelistClasses:(id)arg1;
+ (void)sim_securelyWhitelistClass:(Class)arg1;
+ (id)sim_securelyWhitelistClasses;
@end
