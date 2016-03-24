/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "NSPredicate+FBControlCore.h"

#import <AppKit/AppKit.h>

@implementation NSPredicate (FBControlCore)

#pragma mark Public

+ (NSPredicate *)predicateForVideoPaths
{
  return [self predicateForPathsMatchingUTIs:@[(NSString *)kUTTypeMovie, (NSString *)kUTTypeMPEG4, (NSString *)kUTTypeQuickTimeMovie]];
}

+ (NSPredicate *)predicateForPhotoPaths
{
  return [self predicateForPathsMatchingUTIs:@[(NSString *)kUTTypeImage, (NSString *)kUTTypePNG, (NSString *)kUTTypeJPEG, (NSString *)kUTTypeJPEG2000]];
}

+ (NSPredicate *)predicateForMediaPaths
{
  return [NSCompoundPredicate orPredicateWithSubpredicates:@[
    self.predicateForVideoPaths,
    self.predicateForPhotoPaths
  ]];
}

+ (NSPredicate *)notNullPredicate
{
  return [NSPredicate predicateWithFormat:@"self != nil"];
}

#pragma mark Private

+ (NSPredicate *)predicateForPathsMatchingUTIs:(NSArray<NSString *> *)utis
{
  NSSet<NSString *> *utiSet = [NSSet setWithArray:utis];
  NSWorkspace *workspace = NSWorkspace.sharedWorkspace;
  return [self predicateWithBlock:^ BOOL (NSString *path, NSDictionary *_) {
    NSString *uti = [workspace typeOfFile:path error:nil];
    return [utiSet containsObject:uti];
  }];
}

@end
