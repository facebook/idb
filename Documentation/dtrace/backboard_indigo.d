/* vim: set tabstop=2 shiftwidth=2 filetype=dtrace: */
/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */
/* Tracing of Indigo Messages in backboardd */

#include <SimulatorApp/Mach.h>
#include <SimulatorApp/Indigo.h>
#include <SimulatorApp/Purple.h>

/*
pid$target::IOHIDEvent*:return
{
}
*/

pid$target::IOHIDEventCreateDigitizerEvent:return
{
}

pid$target::IOHIDEventCreateKeyboardEvent:return
{
}
