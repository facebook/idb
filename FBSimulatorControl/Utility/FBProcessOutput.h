/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The Termination Handle Type for Process Output.
 */
extern FBTerminationHandleType const FBTerminationHandleTypeProcessOutput;

/**
 Wraps the output of a Process.
 */
@interface FBProcessOutput : NSObject <FBTerminationHandle>

/**
 An Output Container for a File Handle.

 @param fileHandle the File Handle.
 */
+ (instancetype)outputForFileHandle:(NSFileHandle *)fileHandle diagnostic:(FBDiagnostic *)diagnostic;

/**
 An Output Container for a File Consumer.
 */
+ (nullable instancetype)outputWithConsumer:(id<FBFileConsumer>)consumer error:(NSError **)error;

/**
 The File Handle.
 */
@property (nonatomic, strong, readonly) NSFileHandle *fileHandle;

/**
 The Diagnostic.
 */
@property (nonatomic, strong, nullable, readonly) FBDiagnostic *diagnostic;

@end

NS_ASSUME_NONNULL_END
