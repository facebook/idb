/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 * Manages the photo library on the simulator via the Photos framework
 * and PLPhotoLibrary private API. Uses CoreData directly to delete
 * photo assets from the managed object context, bypassing the public
 * PHPhotoLibrary change request API (which requires user confirmation).
 *
 * Usage:
 *   handlePhotoLibraryAction(@"clear")  // Delete all photos
 *
 * @param action "clear"
 * @return 0 on success, 1 on failure
 */
int handlePhotoLibraryAction(NSString *action);
