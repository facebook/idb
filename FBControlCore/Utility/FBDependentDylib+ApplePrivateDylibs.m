/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDependentDylib+ApplePrivateDylibs.h"
#import "FBControlCoreGlobalConfiguration.h"

@implementation FBDependentDylib (ApplePrivateDylibs)

+ (NSArray<FBDependentDylib *> *)SwiftDylibs
{

  // Starting in Xcode 8.3, IDEFoundation.framework requires Swift libraries to be loaded
  // prior to loading the framework itself.
  //
  // You can inspect what libraries are loaded and in what order using:
  //
  // $ xcrun otool -l Xcode.app/Contents/Frameworks/IDEFoundation.framework
  //
  // The minimum macOS version for Xcode 8.3 is Sierra 10.12 so there is no need to
  // branch on the macOS version.
  //
  // The order matters!  The first swift dylib loaded by IDEFoundation.framework is
  // AppKit.  However, AppKit requires CoreImage and QuartzCore to be loaded first.

  NSDecimalNumber *xcodeVersion = [FBControlCoreGlobalConfiguration xcodeVersionNumber];
  NSDecimalNumber *xcode83 = [NSDecimalNumber decimalNumberWithString:@"8.3"];
  BOOL atLeastXcode83 = [xcodeVersion compare:xcode83] != NSOrderedAscending;

  if (atLeastXcode83) {
    return @[
             [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftCoreImage.dylib"],
             [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftQuartzCore.dylib"],
             [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftAppKit.dylib"],
             [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftCore.dylib"],
             [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftCoreData.dylib"],
             [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftCoreGraphics.dylib"],
             [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftDarwin.dylib"],
             [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftDispatch.dylib"],
             [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftFoundation.dylib"],
             [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftIOKit.dylib"],
             [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftObjectiveC.dylib"],
             [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftXPC.dylib"]
             ];
  } else {
    // No swift dylibs are required.
    return @[];
  }
}

@end
