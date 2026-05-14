/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A Double for verifiying callers of FBXCTestReporter
 */
@interface FBXCTestReporterDouble : NSObject <FBXCTestReporter>

/**
 An array of the started test suites.
 */
@property (nonatomic, readonly, copy) NSArray<NSString *> *startedSuites;

/**
 An array of ended test suites
 */
@property (nonatomic, readonly, copy) NSArray<NSString *> *endedSuites;

/**
 An array of called test class/method pairs.
 */
@property (nonatomic, readonly, copy) NSArray<NSArray<NSString *> *> *startedTests;

/**
 An array of passed test class/method pairs.
 */
@property (nonatomic, readonly, copy) NSArray<NSArray<NSString *> *> *passedTests;

/**
 An array of failed test class/method pairs.
 */
@property (nonatomic, readonly, copy) NSArray<NSArray<NSString *> *> *failedTests;

/**
 Confirmation -[FBXCTestReporter printReportWithError:] was called.
 */
@property (nonatomic, readonly, assign) BOOL printReportWasCalled;

/**
 Path to logs directory
 */
@property (nullable, nonatomic, copy) NSString *logDirectoryPath;

/**
 Get events by name that were received from `-[FBXCTestReporter handleExternalEvent:]`
 */
- (NSArray<NSDictionary *> *)eventsWithName:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
