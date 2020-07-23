/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBiOSTargetDiagnostics.h"

#import "FBDiagnostic.h"
#import "FBDiagnosticQuery.h"
#import "FBiOSTarget.h"

FBDiagnosticName const FBDiagnosticNameVideo = @"video";
FBDiagnosticName const FBDiagnosticNameSyslog = @"system_log";
FBDiagnosticName const FBDiagnosticNameScreenshot = @"screenshot";

@interface FBDiagnosticQuery (FBiOSTargetDiagnostics)

- (NSArray<FBDiagnostic *> *)perform:(FBiOSTargetDiagnostics *)diagnostics;

@end

@implementation FBiOSTargetDiagnostics

#pragma mark Initializers

- (instancetype)initWithStorageDirectory:(NSString *)storageDirectory
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _storageDirectory = storageDirectory;

  return self;
}

#pragma mark - Public

- (FBDiagnostic *)base
{
  return [self.baseLogBuilder build];
}

- (FBDiagnostic *)video
{
  return [[[[self.baseLogBuilder
    updateShortName:FBDiagnosticNameVideo]
    updateFileType:@"mp4"]
    updatePath:FBiOSTargetDefaultVideoPath(self.storageDirectory)]
    build];
}

- (FBDiagnosticBuilder *)baseLogBuilder
{
  return [FBDiagnosticBuilder.builder updateStorageDirectory:self.storageDirectory];
}

- (NSArray<FBDiagnostic *> *)allDiagnostics
{
  NSArray<FBDiagnostic *> *diagnostics = @[
    self.video,
  ];
  return [diagnostics filteredArrayUsingPredicate:FBiOSTargetDiagnostics.predicateForHasContent];
}

- (NSDictionary<NSString *, FBDiagnostic *> *)namedDiagnostics
{
  NSMutableDictionary<NSString *, FBDiagnostic *> *dictionary = [NSMutableDictionary dictionary];
  for (FBDiagnostic *diagnostic in self.allDiagnostics) {
    if (!diagnostic.shortName) {
      continue;
    }
    dictionary[diagnostic.shortName] = diagnostic;
  }
  return [dictionary copy];
}

- (NSArray<FBDiagnostic *> *)diagnosticsForApplicationWithBundleID:(nullable NSString *)bundleID withFilenames:(NSArray<NSString *> *)filenames withFilenameGlobs:(nonnull NSArray<NSString *> *)filenameGlobs fallbackToGlobalSearch:(BOOL)globalFallback
{
  return @[];
}

+ (NSPredicate *)predicateForHasContent
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBDiagnostic *diagnostic, NSDictionary *_) {
    return diagnostic.hasLogContent;
  }];
}

@end
