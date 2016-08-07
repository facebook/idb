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

NS_ASSUME_NONNULL_BEGIN

/**
 A Test Reporter that implements the FBTestManagerTestReporter interface.
 It writes the Test Result to a given File Handle in the JUnit XML format.
 */
@interface FBTestManagerTestReporterJUnit : NSObject <FBTestManagerTestReporter>

/**
 Constructs a JUnit Test Reporter.

 @param outputFileHandle a file handle the JUnit XML should be written to.
 */
+ (instancetype)withOutputFileHandle:(NSFileHandle *)outputFileHandle;

@end

NS_ASSUME_NONNULL_END
