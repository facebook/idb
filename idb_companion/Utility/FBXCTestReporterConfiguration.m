/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestReporterConfiguration.h"

#import <FBControlCore/FBControlCore.h>

@implementation FBXCTestReporterConfiguration

- (instancetype)initWithResultBundlePath:(nullable NSString *)resultBundlePath coverageDirectoryPath:(nullable NSString *)coverageDirectoryPath logDirectoryPath:(nullable NSString *)logDirectoryPath binariesPaths:(nullable NSArray<NSString *> *)binariesPaths reportAttachments:(BOOL)reportAttachments
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _resultBundlePath = resultBundlePath;
  _coverageDirectoryPath = coverageDirectoryPath;
  _logDirectoryPath = logDirectoryPath;
  _binariesPaths = binariesPaths;
  _reportAttachments = reportAttachments;

  return self;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Result Bundle %@ | Coverage Directory Path %@ | Log Path %@ | Binaries Paths %@ | Report Attachments %d", self.resultBundlePath, self.coverageDirectoryPath, self.logDirectoryPath, [FBCollectionInformation oneLineDescriptionFromArray:self.binariesPaths], self.reportAttachments];
}

@end
