/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/NSKeyedUnarchiver.h>

@interface NSKeyedUnarchiver (SimSecurely)
+ (id)sim_securelyUnarchiveObjectWithClasses:(id)arg1 data:(id)arg2;
+ (id)sim_securelyUnarchiveObjectWithData:(id)arg1;
+ (void)sim_securelyWhitelistClasses:(id)arg1;
+ (void)sim_securelyWhitelistClass:(Class)arg1;
+ (id)sim_securelyWhitelistClasses;
@end
