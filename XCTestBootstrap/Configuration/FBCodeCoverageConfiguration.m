/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBCodeCoverageConfiguration.h"


@implementation FBCodeCoverageConfiguration

-(instancetype) initWithDirectory:(NSString *)coverageDirectory format:(FBCodeCoverageFormat)format coverageFileSuffix:(NSString *)coverageFileSuffix
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _coverageDirectory = coverageDirectory;
  _format = format;
  _coverageFileSuffix = coverageFileSuffix;

  return self;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Coverage Directory %@ | Format %lu | File Suffix '%@'", self.coverageDirectory, (unsigned long)self.format, self.coverageFileSuffix];
}


@end
