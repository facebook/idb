/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBiOSTargetDiagnostics.h"

#import "FBDiagnostic.h"
#import "FBDiagnosticQuery.h"

NSString *const FBiOSTargetLogNameVideo = @"video";

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
    updateShortName:FBiOSTargetLogNameVideo]
    updateFileType:@"mp4"]
    updatePathFromDefaultLocation]
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

- (NSArray<FBDiagnostic *> *)perform:(FBDiagnosticQuery *)query
{
  return [query perform:self];
}

+ (NSPredicate *)predicateForHasContent
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBDiagnostic *diagnostic, NSDictionary *_) {
    return diagnostic.hasLogContent;
  }];
}

@end

@implementation FBDiagnosticQuery_All (iOSTarget)

- (NSArray<FBDiagnostic *> *)perform:(FBiOSTargetDiagnostics *)diagnostics
{
  return [diagnostics allDiagnostics];
}

@end

@implementation FBDiagnosticQuery_Named (iOSTarget)

- (NSArray<FBDiagnostic *> *)perform:(FBiOSTargetDiagnostics *)diagnostics
{
  return [[[diagnostics namedDiagnostics]
    objectsForKeys:self.names notFoundMarker:(id)NSNull.null]
    filteredArrayUsingPredicate:NSPredicate.notNullPredicate];
}

@end

@implementation FBDiagnosticQuery (iOSTarget)

- (NSArray<FBDiagnostic *> *)perform:(FBSimulatorDiagnostics *)diagnostics
{
  return @[];
}

@end
