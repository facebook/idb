/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "AppDelegate.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
  [self.window makeKeyAndVisible];
  self.window.rootViewController = [UIViewController new];
  self.window.rootViewController.view.backgroundColor = [UIColor whiteColor];

  UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
  [self.window.rootViewController.view addSubview:button];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  [button setTitle:@"PING" forState:UIControlStateNormal];
  [button addTarget:self action:@selector(ping:) forControlEvents:UIControlEventTouchUpInside];
  [button.centerXAnchor constraintEqualToAnchor:self.window.rootViewController.view.centerXAnchor].active = YES;
  [button.centerYAnchor constraintEqualToAnchor:self.window.rootViewController.view.centerYAnchor].active = YES;
  return YES;
}

- (void)ping:(UIButton *)sender
{
  if ([sender.titleLabel.text isEqualToString:@"PING"]) {
    [sender setTitle:@"PONG" forState:UIControlStateNormal];
  } else {
    [sender setTitle:@"PING" forState:UIControlStateNormal];
  }
}

@end
