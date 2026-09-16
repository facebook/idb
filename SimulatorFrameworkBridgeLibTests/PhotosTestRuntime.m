/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "PhotosTestRuntime.h"

#import <SimulatorFrameworkBridgeLib/PhotoLibraryService+Testing.h>

@interface FBPhotosTestRuntime ()
@property (nonatomic) BOOL insideTransaction;
@property (nonatomic) BOOL allMutationsInsideTransaction;
@end

@interface FBPhotoProbe : NSObject
@property (nonatomic, weak) FBPhotosTestRuntime *runtime;
@property (nonatomic) NSUInteger index;
@end

@implementation FBPhotoProbe
- (id)valueForKey:(NSString *)key
{
  [self.runtime.operations addObject:[@"value:" stringByAppendingString:key]];
  if ([self.runtime.failure isEqualToString:@"lazyException"]) {
    [NSException raise:@"PhotosTest" format:@"lazy lookup failed"];
  }
  return self;
}

- (id)objectValue
{
  [self.runtime.operations addObject:@"unwrap"];
  if ([self.runtime.failure isEqualToString:@"unwrapException"]) {
    [NSException raise:@"PhotosTest" format:@"unwrap failed"];
  }
  return [self.runtime.failure isEqualToString:@"libraryMissing"] ? nil : self;
}

- (void)performTransactionAndWait:(void (^)(void))block
{
  [self.runtime.operations addObject:@"transactionBegin"];
  if ([self.runtime.failure isEqualToString:@"transactionException"]) {
    [NSException raise:@"PhotosTest" format:@"transaction failed"];
  }
  self.runtime.insideTransaction = YES;
  @try {
    block();
  } @finally {
    self.runtime.insideTransaction = NO;
    [self.runtime.operations addObject:@"transactionEnd"];
  }
}

- (id)managedObjectContext
{
  [self.runtime.operations addObject:@"context"];
  if ([self.runtime.failure isEqualToString:@"contextException"]) {
    [NSException raise:@"PhotosTest" format:@"context failed"];
  }
  return [self.runtime.failure isEqualToString:@"contextMissing"] ? nil : self;
}

- (NSString *)localIdentifier
{
  return [NSString stringWithFormat:@"asset%lu", (unsigned long)self.index];
}

- (id)objectID
{
  [self.runtime.operations addObject:[@"id:" stringByAppendingString:self.localIdentifier]];
  if ([self.runtime.failure isEqualToString:@"idException"]) {
    [NSException raise:@"PhotosTest" format:@"objectID failed"];
  }
  return [self.runtime.failure isEqualToString:@"idMissing"] ? nil : self.localIdentifier;
}

- (id)objectWithID:(id)objectID
{
  [self.runtime.operations addObject:[@"lookup:" stringByAppendingString:objectID]];
  self.runtime.allMutationsInsideTransaction &= self.runtime.insideTransaction;
  if ([self.runtime.failure isEqualToString:@"lookupException"]) {
    [NSException raise:@"PhotosTest" format:@"lookup failed"];
  }
  return [self.runtime.failure isEqualToString:@"objectMissing"] ? nil : objectID;
}

- (void)deleteObject:(id)object
{
  [self.runtime.operations addObject:[@"delete:" stringByAppendingString:object]];
  self.runtime.allMutationsInsideTransaction &= self.runtime.insideTransaction;
  if ([self.runtime.failure isEqualToString:@"deleteException"]) {
    [NSException raise:@"PhotosTest" format:@"delete failed"];
  }
}

- (BOOL)save:(NSError **)error
{
  [self.runtime.operations addObject:@"save"];
  self.runtime.allMutationsInsideTransaction &= self.runtime.insideTransaction;
  if ([self.runtime.failure isEqualToString:@"saveException"]) {
    [NSException raise:@"PhotosTest" format:@"save failed"];
  }
  if (!self.runtime.saveSucceeds && error) {
    *error = [NSError errorWithDomain:@"PhotosTest" code:1 userInfo:nil];
  }
  return self.runtime.saveSucceeds;
}

@end

@implementation FBPhotosTestRuntime
- (instancetype)init
{
  self = [super init];
  if (self) {
    _assetCount = 2;
    _failure = @"";
    _saveSucceeds = YES;
    _allMutationsInsideTransaction = YES;
    _operations = [NSMutableArray array];
  }
  return self;
}

- (int)run
{
  FBPhotoProbe *library = [FBPhotoProbe new];
  library.runtime = self;
  NSMutableArray *assets = [NSMutableArray array];
  for (NSUInteger index = 0; index < self.assetCount; index++) {
    FBPhotoProbe *asset = [FBPhotoProbe new];
    asset.runtime = self;
    asset.index = index;
    [assets addObject:asset];
  }
  return FBPhotoLibraryClearWithLibrary((PHPhotoLibrary *)library, (PHFetchResult<PHAsset *> *)assets);
}

- (NSDictionary<NSString *, id> *)runCatchingException
{
  @try {
    return @{@"status" : @([self run])};
  } @catch (NSException *exception) {
    return @{@"exception" : exception.name};
  }
}

@end
