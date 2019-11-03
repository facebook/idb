/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestManagerTestReporter.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A Test Reporter that implements the FBTestManagerTestReporter interface.
 It forwards all method invocations to a given list of other Test Reporters,
 which also implement the FBTestManagerTestReporter interface.
 */
@interface FBTestManagerTestReporterComposite : NSObject <FBTestManagerTestReporter>

/**
 Constructs a Test Reporter with a given List of Other Test Reporters.

 @param reporters array of reporters implementing FBTestManagerTestReporter.
 @return a new Composite Test Reporter instance.
 */
+ (instancetype)withTestReporters:(NSArray<id<FBTestManagerTestReporter>> *)reporters;

@end

NS_ASSUME_NONNULL_END
