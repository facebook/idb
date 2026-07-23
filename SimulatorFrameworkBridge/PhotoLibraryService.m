/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "PhotoLibraryService.h"

#import "PhotosPrivate.h"

static PLPhotoLibrary *getPLPhotoLibrary(PHPhotoLibrary *photoLibrary)
{
  @try {
    id lazyPhotoLibrary = [photoLibrary valueForKey:@"_lazyPhotoLibrary"];
    return [lazyPhotoLibrary objectValue];
  } @catch (NSException *exception) {
    NSLog(@"Failed to access PLPhotoLibrary: %@", exception);
    return nil;
  }
}

static BOOL deletePhotosFromManagedObjectContext(NSManagedObjectContext *moc, PHFetchResult<PHAsset *> *allPhotos)
{
  for (PHAsset *asset in allPhotos) {
    NSManagedObjectID *objectID = asset.objectID;
    if (!objectID) {
      NSLog(@"Failed to get objectID for photo asset %@", asset.localIdentifier);
      return NO;
    }

    @try {
      NSManagedObject *managedObject = [moc objectWithID:objectID];
      if (!managedObject) {
        NSLog(@"Failed to get managedObject for photo asset %@", asset.localIdentifier);
        return NO;
      }
      [moc deleteObject:managedObject];
    } @catch (NSException *exception) {
      NSLog(@"Failed to delete photo asset %@: %@", asset.localIdentifier, exception);
      return NO;
    }
  }

  return YES;
}

static BOOL saveManagedObjectContext(NSManagedObjectContext *moc, NSError **outError)
{
  return [moc save:outError];
}

static int clearPhotoLibrary(void)
{
  PHPhotoLibrary *photoLibrary = [PHPhotoLibrary sharedPhotoLibrary];

  PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];
  PHFetchResult<PHAsset *> *allPhotos = [PHAsset fetchAssetsWithOptions:fetchOptions];

  if (allPhotos.count == 0) {
    NSLog(@"No photos to delete");
    return 0;
  }

  NSLog(@"Found %lu photos to delete", (unsigned long)allPhotos.count);

  PLPhotoLibrary *plPhotoLibrary = getPLPhotoLibrary(photoLibrary);
  if (!plPhotoLibrary) {
    NSLog(@"PLPhotoLibrary not available");
    return 1;
  }

  __block BOOL success = NO;
  __block NSError *transactionError = nil;
  [plPhotoLibrary performTransactionAndWait:^{
    NSManagedObjectContext *moc = nil;
    @try {
      moc = plPhotoLibrary.managedObjectContext;
    } @catch (NSException *exception) {
      return;
    }

    if (!moc) {
      return;
    }

    if (!deletePhotosFromManagedObjectContext(moc, allPhotos)) {
      NSLog(@"Failed to delete all photos");
      return;
    }

    success = saveManagedObjectContext(moc, &transactionError);
  }];

  if (success) {
    NSLog(@"Successfully deleted all photos");
    return 0;
  }

  NSLog(@"PLPhotoLibrary transaction completed but success was NO. Error: %@", transactionError);
  return 1;
}

int handlePhotoLibraryAction(NSString *action)
{
  if ([action isEqualToString:@"clear"]) {
    return clearPhotoLibrary();
  } else {
    NSLog(@"Unknown action: %@", action);
    return 1;
  }
}
