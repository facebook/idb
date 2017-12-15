/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBiOSTargetCommandForwarder.h>

NS_ASSUME_NONNULL_BEGIN

/**
 An enum for Screenshot Formats.
 */
typedef NSString *FBScreenshotFormat NS_STRING_ENUM;
extern FBScreenshotFormat const FBScreenshotFormatJPEG;
extern FBScreenshotFormat const FBScreenshotFormatPNG;

/**
 Defines the protocol for taking screenshots.
 */
@protocol FBScreenshotCommands <NSObject, FBiOSTargetCommand>

/**
 Takes a Screenshot

 @param format the format of the data.
 @return A Future, wrapping Data of the provided format.
 */
- (FBFuture<NSData *> *)takeScreenshot:(FBScreenshotFormat)format;

@end

NS_ASSUME_NONNULL_END

