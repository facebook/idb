/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <XCTestBootstrap/FBTestManagerTestReporterBase.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A Test Reporter that implements the FBTestManagerTestReporter interface.
 It writes the Test Result to a given File Handle in the JUnit XML format.
 */
@interface FBTestManagerTestReporterJUnit : FBTestManagerTestReporterBase

/**
 Constructs a JUnit Test Reporter.

 @param outputFileURL a URL to a file the JUnit XML should be written to.
 @return a new JUnit Test Reporter instance.
 */
+ (instancetype)withOutputFileURL:(NSURL *)outputFileURL;

@end

NS_ASSUME_NONNULL_END
