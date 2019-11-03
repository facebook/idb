/*
 * Copyright (c) Facebook, Inc. and its affiliates.
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
 An array of called test class/method pairs.
 */
@property (nonatomic, copy, readonly) NSArray<NSArray<NSString *> *> *startedTests;

/**
 An array of passed test class/method pairs.
 */
@property (nonatomic, copy, readonly) NSArray<NSArray<NSString *> *> *passedTests;

/**
 An array of failed test class/method pairs.
 */
@property (nonatomic, copy, readonly) NSArray<NSArray<NSString *> *> *failedTests;

/**
 An array of the started test suites.
 */
@property (nonatomic, copy, readonly) NSArray<NSString *> *startedSuites;

/**
 Confirmation -[FBXCTestReporter printReportWithError:] was called.
 */
@property (nonatomic, assign, readonly) BOOL printReportWasCalled;

/**
 Get events by name that were recieved from `-[FBXCTestReporter handleExternalEvent:]`
 */
- (NSArray<NSDictionary *> *)eventsWithName:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
