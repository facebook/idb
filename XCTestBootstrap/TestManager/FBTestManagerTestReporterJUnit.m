/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
