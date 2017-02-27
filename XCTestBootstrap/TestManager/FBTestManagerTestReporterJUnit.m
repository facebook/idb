/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTestManagerTestReporterJUnit.h"
#import "FBTestManagerJUnitGenerator.h"

@interface FBTestManagerTestReporterJUnit ()

@property (nonatomic, strong) NSURL *outputFileURL;

@end

@implementation FBTestManagerTestReporterJUnit

+ (instancetype)withOutputFileURL:(NSURL *)outputFileURL
{
  return [[self alloc] initWithOutputFileURL:outputFileURL];
}

- (instancetype)initWithOutputFileURL:(NSURL *)outputFileURL
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _outputFileURL = outputFileURL;

  return self;
}

#pragma mark - FBTestManagerTestReporter

- (void)testManagerMediatorDidFinishExecutingTestPlan:(FBTestManagerAPIMediator *)mediator
{
  [super testManagerMediatorDidFinishExecutingTestPlan:mediator];

  NSXMLDocument *document = [FBTestManagerJUnitGenerator documentForTestSuite:self.testSuite];
  [[document XMLDataWithOptions:NSXMLNodePrettyPrint] writeToURL:self.outputFileURL atomically:YES];
}

@end
