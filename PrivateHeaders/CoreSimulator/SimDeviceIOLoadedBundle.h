/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class NSBundle;
@protocol SimDeviceIOBundleInterface;

@interface SimDeviceIOLoadedBundle : NSObject
{
    NSBundle *_bundle;
    id<SimDeviceIOBundleInterface> _bundleInterface;
}

+ (id)loadedBundleForURL:(id)arg1;
@property (retain, nonatomic) id<SimDeviceIOBundleInterface> bundleInterface;
@property (retain, nonatomic) NSBundle *bundle;

- (id)initWithURL:(id)arg1;

@end
