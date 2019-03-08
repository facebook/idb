/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBBundleDescriptor.h>
#import <FBControlCore/FBApplicationBundle.h>
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBControlCoreLogger;

/**
 Enumerations for possible header magic numbers in files & data.
 */
typedef enum {
  FBFileHeaderMagicUnknown = 0,
  FBFileHeaderMagicTAR = 1,
  FBFileHeaderMagicIPA = 2,
} FBFileHeaderMagic;

/**
 A value for an extracted application.
 */
@interface FBExtractedApplication : NSObject

/**
 The extracted Application Bundle.
 */
@property (nonatomic, copy, readonly) FBApplicationBundle *bundle;

/**
 The location of the extracted application on disk.
 */
@property (nonatomic, copy, readonly) NSURL *extractedPath;

@end

/**
 A Bundle Descriptor specialized to Applications
 */
@interface FBApplicationBundle (Install)

#pragma mark Public Methods

/**
 Obtains an extracted version of an Application based on a file path.
 When the context is torn down, any extracted path will be deleted.

 @param queue the queue to extract on.
 @param path the path of the .app or .ipa
 @param logger the (optional) logger to log to.
 @return a future wrapping the extracted application.
 */
+ (FBFutureContext<FBExtractedApplication *> *)onQueue:(dispatch_queue_t)queue findOrExtractApplicationAtPath:(NSString *)path logger:(nullable id<FBControlCoreLogger>)logger;

/**
 Copy additional framework to Application path.

 @param appPath the path of the .app.
 @param frameworkPath the path of the framework.
 @return a future wrapping the application path.
 */
+ (NSString *)copyFrameworkToApplicationAtPath:(NSString *)appPath frameworkPath:(NSString *)frameworkPath;

/**
 Check if given path is an application path.

 @param path the path to check.
 @return if the path is an application path.
 */
+ (BOOL)isApplicationAtPath:(NSString *)path;

/**
 Check if given NSData is an ipa or a tar

 @param data the data to check.
 @return the header magic if one could be deduced.
 */
+ (FBFileHeaderMagic)headerMagicForData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
