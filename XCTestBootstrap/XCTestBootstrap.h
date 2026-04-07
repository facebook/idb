/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTestBootstrap/FBActivityRecord.h>
#import <XCTestBootstrap/FBAttachment.h>
#import <XCTestBootstrap/FBCodeCoverageConfiguration.h>
#import <XCTestBootstrap/FBLogicXCTestReporter.h>
#import <XCTestBootstrap/FBTestBundleConnection.h>
#import <XCTestBootstrap/FBTestConfiguration.h>
#import <XCTestBootstrap/FBTestManagerAPIMediator.h>
#import <XCTestBootstrap/FBTestManagerResultSummary.h>
#import <XCTestBootstrap/FBTestRunnerConfiguration.h>
#import <XCTestBootstrap/FBXCTestConfiguration.h>
#import <XCTestBootstrap/FBXCTestReporter.h>
#import <XCTestBootstrap/FBXCTestRunner.h>
#import <XCTestBootstrap/XCTestBootstrapError.h>

// Note: FBTestReporterAdapter.h is intentionally excluded as it imports XCTestPrivate headers

#if __has_include(<XCTestBootstrap/XCTestBootstrap-Swift.h>)
 #import <XCTestBootstrap/XCTestBootstrap-Swift.h>
#endif
