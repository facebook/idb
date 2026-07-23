/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Synthetic header for Photos private API.
//
// The public PHPhotoLibrary API requires user confirmation dialogs for
// destructive operations (PHAssetChangeRequest). To clear photos in
// automated tests, we bypass this by accessing the private PLPhotoLibrary
// layer and manipulating the CoreData managed object context directly.
//
// Access chain:
//   PHPhotoLibrary → _lazyPhotoLibrary (ivar) → objectValue → PLPhotoLibrary

#import <CoreData/CoreData.h>
#import <Foundation/Foundation.h>
#import <Photos/Photos.h>

/**
 * Private implementation behind PHPhotoLibrary. Manages the CoreData
 * persistent store that backs the photo library. Accessed by unwrapping
 * PHPhotoLibrary's private _lazyPhotoLibrary ivar.
 */
@interface PLPhotoLibrary : NSObject

/**
 * Executes a block within a CoreData transaction on the photo library's
 * private serial queue, blocking until the block completes. All CoreData
 * mutations (delete, save) must happen inside this transaction.
 */
- (void)performTransactionAndWait:(void (^)(void))block;

/**
 * The CoreData NSManagedObjectContext backing the photo library's
 * persistent store. Used to look up and delete managed objects
 * corresponding to PHAsset instances.
 */
@property (nonatomic, readonly) NSManagedObjectContext *managedObjectContext;

@end

/**
 * PHPhotoLibrary stores PLPhotoLibrary inside a lazy initialization
 * wrapper. The concrete wrapper class is an implementation detail —
 * objectValue unwraps it to return the actual PLPhotoLibrary instance.
 */
@interface NSObject (LazyObjectValue)
- (id)objectValue;
@end

/**
 * PHAsset is backed by a CoreData managed object. This property
 * exposes the NSManagedObjectID, used to look up the corresponding
 * NSManagedObject in PLPhotoLibrary's managed object context for
 * direct deletion.
 */
@interface PHAsset (CoreDataPrivate)
@property (nonatomic, readonly) NSManagedObjectID *objectID;
@end
