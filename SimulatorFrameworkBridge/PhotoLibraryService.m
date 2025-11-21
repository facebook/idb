/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>
#import <objc/message.h>

@interface NSObject (PLPhotoLibraryPrivate)
- (void)performTransactionAndWait:(void (^)(void))block;
@end

static id getPLPhotoLibrary(PHPhotoLibrary *photoLibrary) {
    id lazyPhotoLibrary = nil;
    id plPhotoLibrary = nil;

    @try {
      lazyPhotoLibrary = [photoLibrary valueForKey:@"_lazyPhotoLibrary"];
      if (lazyPhotoLibrary && [lazyPhotoLibrary respondsToSelector:@selector(objectValue)]) {
        id (*objectValue)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
        plPhotoLibrary = objectValue(lazyPhotoLibrary, @selector(objectValue));
      }
    } @catch (NSException *exception) {
      NSLog(@"Failed to access PLPhotoLibrary: %@", exception);
      return nil;
    }

    return plPhotoLibrary;
}

static BOOL deletePhotosFromManagedObjectContext(id managedObjectContext, PHFetchResult<PHAsset *> *allPhotos) {
    for (PHAsset *asset in allPhotos) {
      id objectID = [asset valueForKey:@"objectID"];
      if (!objectID) {
        NSLog(@"Failed to get objectID for photo asset %@", asset.localIdentifier);
        return NO;
      }

      @try {
        if (![managedObjectContext respondsToSelector:@selector(objectWithID:)]) {
          NSLog(@"managedObjectContext does not respond to objectWithID:");
          return NO;
        }

        id (*objectWithID)(id, SEL, id) = (id (*)(id, SEL, id))objc_msgSend;
        id managedObject = objectWithID(managedObjectContext, @selector(objectWithID:), objectID);

        if (!managedObject) {
          NSLog(@"Failed to get managedObject for photo asset %@", asset.localIdentifier);
          return NO;
        }

        if (![managedObjectContext respondsToSelector:@selector(deleteObject:)]) {
          NSLog(@"managedObjectContext does not respond to deleteObject:");
          return NO;
        }

        void (*deleteObject)(id, SEL, id) = (void (*)(id, SEL, id))objc_msgSend;
        deleteObject(managedObjectContext, @selector(deleteObject:), managedObject);
      } @catch (NSException *exception) {
        NSLog(@"Failed to delete photo asset %@: %@", asset.localIdentifier, exception);
        return NO;
      }
    }

    return YES;
}

static BOOL saveManagedObjectContext(id managedObjectContext, NSError **outError) {
    if (![managedObjectContext respondsToSelector:@selector(save:)]) {
      return NO;
    }

    NSMethodSignature *signature = [managedObjectContext methodSignatureForSelector:@selector(save:)];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setTarget:managedObjectContext];
    [invocation setSelector:@selector(save:)];

    NSError *error = nil;
    [invocation setArgument:&error atIndex:2];
    [invocation invoke];

    BOOL saveResult = NO;
    [invocation getReturnValue:&saveResult];

    if (!saveResult && outError) {
      *outError = error;
    }

    return saveResult;
}

static int clearPhotoLibrary(void) {
    PHPhotoLibrary *photoLibrary = [PHPhotoLibrary sharedPhotoLibrary];

    PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];
    PHFetchResult<PHAsset *> *allPhotos = [PHAsset fetchAssetsWithOptions:fetchOptions];

    if (allPhotos.count == 0) {
      NSLog(@"No photos to delete");
      return 0;
    }

    NSLog(@"Found %lu photos to delete", (unsigned long)allPhotos.count);

    id plPhotoLibrary = getPLPhotoLibrary(photoLibrary);
    if (!plPhotoLibrary) {
      NSLog(@"PLPhotoLibrary not available");
      return 1;
    }

    if (![plPhotoLibrary respondsToSelector:@selector(performTransactionAndWait:)]) {
      NSLog(@"PLPhotoLibrary does not respond to performTransactionAndWait:");
      return 1;
    }

    __block BOOL success = NO;
    __block NSError *transactionError = nil;
    void (^transactionBlock)(void) = ^{
      id managedObjectContext = nil;
      @try {
        managedObjectContext = [plPhotoLibrary valueForKey:@"managedObjectContext"];
      } @catch (NSException *exception) {
        return;
      }

      if (!managedObjectContext) {
        return;
      }

      if (!deletePhotosFromManagedObjectContext(managedObjectContext, allPhotos)) {
        NSLog(@"Failed to delete all photos");
        return;
      }

      success = saveManagedObjectContext(managedObjectContext, &transactionError);
    };

    void (*performTransaction)(id, SEL, id) = (void (*)(id, SEL, id))objc_msgSend;
    performTransaction(plPhotoLibrary, @selector(performTransactionAndWait:), transactionBlock);

    if (success) {
      NSLog(@"Successfully deleted all photos");
      return 0;
    }

    NSLog(@"PLPhotoLibrary transaction completed but success was NO. Error: %@", transactionError);
    return 1;
}

int handlePhotoLibraryAction(NSString *action) {
  if ([action isEqualToString:@"clear"]) {
    return clearPhotoLibrary();
  } else {
    NSLog(@"Unknown action: %@", action);
    return 1;
  }
}
