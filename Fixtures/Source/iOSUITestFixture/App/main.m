/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <UIKit/UIKit.h>

@interface AppDelegate : NSObject <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation AppDelegate
@end

int main(int argc, char * argv[]) {
  @autoreleasepool {
      return UIApplicationMain(argc, argv, nil, @"AppDelegate");
  }
}
