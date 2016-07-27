/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTestManagerTestReporter.h"
#import <Foundation/Foundation.h>

@interface FBTestManagerTestReporterComposite : NSObject <FBTestManagerTestReporter>

/**
 Constructs a Test Reporter with a given List of Other Test Reporters.
 */
+ (instancetype)withTestReporters:(NSArray<id<FBTestManagerTestReporter>> *)reporters;

@end
