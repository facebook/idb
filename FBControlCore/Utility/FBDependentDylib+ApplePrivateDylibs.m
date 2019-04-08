/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

/* Portions Copyright © Microsoft Corporation. */

#import "FBDependentDylib+ApplePrivateDylibs.h"
#import "FBXcodeConfiguration.h"

@implementation FBDependentDylib (ApplePrivateDylibs)

+ (NSArray<FBDependentDylib *> *)SwiftDylibs
{

  // Starting in Xcode 8.3, IDEFoundation.framework requires Swift libraries to
  // be loaded prior to loading the framework itself.
  //
  // You can inspect what libraries are loaded and in what order using:
  //
  // $ xcrun otool -l Xcode.app/Contents/Frameworks/IDEFoundation.framework
  //
  // The minimum macOS version for Xcode 8.3 is Sierra 10.12 so there is no need
  // to branch on the macOS version.
  //
  // The order matters!  The first swift dylib loaded by IDEFoundation.framework
  // is AppKit.  However, AppKit requires CoreImage and QuartzCore to be loaded
  // first.

  NSDecimalNumber *xcodeVersion = FBXcodeConfiguration.xcodeVersionNumber;
  NSDecimalNumber *xcode83 = [NSDecimalNumber decimalNumberWithString:@"8.3"];
  BOOL atLeastXcode83 = [xcodeVersion compare:xcode83] != NSOrderedAscending;

  NSDecimalNumber *xcode90 = [NSDecimalNumber decimalNumberWithString:@"9.0"];
  BOOL atLeastXcode90 = [xcodeVersion compare:xcode90] != NSOrderedAscending;

  NSDecimalNumber *xcode102 = [NSDecimalNumber decimalNumberWithString:@"10.2"];
  BOOL atLeastXcode102 = [xcodeVersion compare:xcode102] != NSOrderedAscending;
  // dylibs not required prior to Xcode 8.3.3
  NSArray *dylibs = @[];
if (atLeastXcode102) {
    dylibs =
    @[
       [FBDependentDylib dependentWithAbsolutePath:@"/usr/lib/swift/libswiftCore.dylib"],
       [FBDependentDylib dependentWithAbsolutePath:@"/usr/lib/swift/libswiftDarwin.dylib"],
       [FBDependentDylib dependentWithAbsolutePath:@"/usr/lib/swift/libswiftObjectiveC.dylib"],
       [FBDependentDylib dependentWithAbsolutePath:@"/usr/lib/swift/libswiftDispatch.dylib"],
       [FBDependentDylib dependentWithAbsolutePath:@"/usr/lib/swift/libswiftCoreFoundation.dylib"],
       [FBDependentDylib dependentWithAbsolutePath:@"/usr/lib/swift/libswiftIOKit.dylib"],
       [FBDependentDylib dependentWithAbsolutePath:@"/usr/lib/swift/libswiftCoreGraphics.dylib"],
       [FBDependentDylib dependentWithAbsolutePath:@"/usr/lib/swift/libswiftFoundation.dylib"],
       [FBDependentDylib dependentWithAbsolutePath:@"/usr/lib/swift/libswiftXPC.dylib"],
       [FBDependentDylib dependentWithAbsolutePath:@"/usr/lib/swift/libswiftos.dylib"],
       [FBDependentDylib dependentWithAbsolutePath:@"/usr/lib/swift/libswiftMetal.dylib"],
       [FBDependentDylib dependentWithAbsolutePath:@"/usr/lib/swift/libswiftCoreImage.dylib"],
       [FBDependentDylib dependentWithAbsolutePath:@"/usr/lib/swift/libswiftQuartzCore.dylib"],
       [FBDependentDylib dependentWithAbsolutePath:@"/usr/lib/swift/libswiftCoreData.dylib"],
       [FBDependentDylib dependentWithAbsolutePath:@"/usr/lib/swift/libswiftAppKit.dylib"]
     ];
} else if (atLeastXcode90) {
    dylibs =
    @[
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftCore.dylib"],
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftDarwin.dylib"],
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftObjectiveC.dylib"],
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftDispatch.dylib"],
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftCoreFoundation.dylib"],
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftIOKit.dylib"],
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftCoreGraphics.dylib"],
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftFoundation.dylib"],
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftXPC.dylib"],
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftos.dylib"],
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftMetal.dylib"],
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftCoreImage.dylib"],
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftQuartzCore.dylib"],
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftCoreData.dylib"],
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftAppKit.dylib"]
      ];
  } else if (atLeastXcode83) {
    dylibs =
    @[
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftCore.dylib"],
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftDarwin.dylib"],
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftObjectiveC.dylib"],
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftDispatch.dylib"],
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftIOKit.dylib"],
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftCoreGraphics.dylib"],
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftFoundation.dylib"],
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftXPC.dylib"],
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftCoreImage.dylib"],
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftQuartzCore.dylib"],
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftCoreData.dylib"],
      [FBDependentDylib dependentWithRelativePath:@"../Frameworks/libswiftAppKit.dylib"]
      ];
  }
  return dylibs;
}

@end
