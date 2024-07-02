/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <objc/runtime.h>

void XTSwizzleClassSelectorForFunction(Class cls, SEL sel, IMP newImp) __attribute__((no_sanitize("nullability-arg")));

void XTSwizzleSelectorForFunction(Class cls, SEL sel, IMP newImp);
