/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

/**
 Operations on a wrapped temporary directory.
 */
@interface FBTemporaryDirectory : NSObject

#pragma mark Initializers

/**
 The Designated Initializer.

 @param logger the logger to use.
 @return a new FBTemporaryDirectory instance.
 */
+ (nonnull instancetype)temporaryDirectoryWithLogger:(nonnull id<FBControlCoreLogger>)logger;

#pragma mark Methods

/**
 Call to clean up the temporary directory.
 */
- (void)cleanOnExit;

/**
 A path to a unique ephemeral temporary directory.
 */
- (nonnull NSURL *)ephemeralTemporaryDirectory;

/**
 Extracts a gzip to a temporary location.

 @param input the input stream of tar data.
 @param name the desitnation name.
 @return a Context Future containing the root of the extraction tar
 */
- (nonnull FBFutureContext<NSURL *> *)withGzipExtractedFromStream:(nonnull FBProcessInput *)input name:(nonnull NSString *)name;

/**
 Extracts archive data to a temporary location.
 For the supported archives see -[FBArchiveOperations extractArchiveAtPath:toPath:overrideModificationTime:queue:logger:]

 @param tarData NSData representation of the tar to extract
 @return a Context Future containing the root of the extraction tar
 */
- (nonnull FBFutureContext<NSURL *> *)withArchiveExtracted:(nonnull NSData *)tarData;

/**
 Extracts a archive stream to a temporary location.
 For the supported archives see -[FBArchiveOperations extractArchiveAtPath:toPath:overrideModificationTime:queue:logger:]

 @param input stream containing tar data
 @param compression archive compression format
 @return a Context Future containing the root of the extraction tar
 */
- (nonnull FBFutureContext<NSURL *> *)withArchiveExtractedFromStream:(nonnull FBProcessInput *)input compression:(FBCompressionFormat)compression;

/**
 Extracts a archive stream to a temporary location.
 For the supported archives see -[FBArchiveOperations extractArchiveAtPath:toPath:overrideModificationTime:queue:logger:]

 @param input stream containing tar data
 @param compression archive compression format
 @param overrideMTime if YES the archive contests' `mtime` will be ignored. Current timestamp will be used as mtime of extracted files/directories.
 @return a Context Future containing the root of the extraction tar
 */
- (nonnull FBFutureContext<NSURL *> *)withArchiveExtractedFromStream:(nonnull FBProcessInput *)input compression:(FBCompressionFormat)compression overrideModificationTime:(BOOL)overrideMTime;

/**
 Extracts an archive file to a temporary location.
 For the supported archives see -[FBArchiveOperations extractArchiveAtPath:toPath:overrideModificationTime:queue:logger:]

 @param filePath the file path to extract
 @return a Context Future containing the root of the extraction tar
 */
- (nonnull FBFutureContext<NSURL *> *)withArchiveExtractedFromFile:(nonnull NSString *)filePath;

/**
 Extracts an archive file to a temporary location.
 For the supported archives see -[FBArchiveOperations extractArchiveAtPath:toPath:overrideModificationTime:queue:logger:]

 @param filePath the file path to extract
 @param overrideMTime if YES the archive contests' `mtime` will be ignored. Current timestamp will be used as mtime of extracted files/directories.
 @return a Context Future containing the root of the extraction tar
 */
- (nonnull FBFutureContext<NSURL *> *)withArchiveExtractedFromFile:(nonnull NSString *)filePath overrideModificationTime:(BOOL)overrideMTime;

/**
 Takes the extraction directory of a tar and returns a list of files contained
 in the subfolders.
 The tar is expected to be of the format
 tar/UDID1/file1
    /UDID2/file2
    /...
 with each subdirectory only containing one file.
 In this case @[file1, file2] would be returned.

 @param extractionDirContext Context wrapping a tar extraction dir
 @return a Context Future containing paths to the files within the dir
 */
- (nonnull FBFutureContext<NSArray<NSURL *> *> *)filesFromSubdirs:(nonnull FBFutureContext<NSURL *> *)extractionDirContext;

#pragma mark Temporary Directory

/**
 A URL for a temporary directory.
 @return a url for the directory
 */
- (nonnull NSURL *)temporaryDirectory;

/**
 A Future Context for a temporary directory.
 Will clean the temporary directory when the context exits.

 @return a Context Future
 */
- (nonnull FBFutureContext<NSURL *> *)withTemporaryDirectory;

#pragma mark Properties

/**
 The logger to log to.
 */
@property (nonnull, nonatomic, readonly, strong) id<FBControlCoreLogger> logger;

/**
 The queue to use.
 */
@property (nonnull, nonatomic, readonly, strong) dispatch_queue_t queue;

@end
