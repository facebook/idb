/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestManagerTestReporterTestCaseFailure.h"

@interface FBTestManagerTestReporterTestCaseFailure ()

@property (nonatomic, assign) NSUInteger line;
@property (nonatomic, copy) NSString *file;
@property (nonatomic, copy) NSString *message;

@end

@implementation FBTestManagerTestReporterTestCaseFailure

+ (instancetype)withMessage:(NSString *)message file:(NSString *)file line:(NSUInteger)line
{
  return [[self alloc] initWithMessage:message file:file line:line];
}

- (instancetype)initWithMessage:(NSString *)message file:(NSString *)file line:(NSUInteger)line
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _message = [message copy];
  _file = [file copy];
  _line = line;

  return self;
}

#pragma mark -

- (NSString *)description
{
  return [NSString stringWithFormat:@"TestFailure %@:%zd | Message %@", self.file, self.line, self.message];
}

@end
