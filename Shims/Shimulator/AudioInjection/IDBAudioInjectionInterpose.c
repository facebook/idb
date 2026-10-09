/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#include <stdlib.h>
#include <string.h>

#include "IDBAudioInjectionPrivate.h"

static bool IDBAudioInjectionArmed;

// Read once at load, before any app code runs. Matches `ShimulatorAudioInjection.armedEnvironmentVariable`.
__attribute__((constructor)) static void IDBAudioInjectionReadArming(void)
{
  const char *value = getenv("IDB_AUDIO_INJECTION");
  IDBAudioInjectionArmed = value != NULL && strcmp(value, "1") == 0;
}

bool IDBAudioInjectionIsArmed(void)
{
  return IDBAudioInjectionArmed;
}

#define IDB_INTERPOSE(replacement, replacee)                                                \
        __attribute__((used, section("__DATA,__interpose"))) static const void *const             \
        IDBInterpose ## replacee[2] = {(const void *)replacement, (const void *)replacee}

IDB_INTERPOSE(IDBAudioDeviceCreateIOProcID, AudioDeviceCreateIOProcID);
IDB_INTERPOSE(IDBAudioDeviceDestroyIOProcID, AudioDeviceDestroyIOProcID);
IDB_INTERPOSE(IDBAudioObjectGetPropertyData, AudioObjectGetPropertyData);
IDB_INTERPOSE(IDBAudioObjectGetPropertyDataSize, AudioObjectGetPropertyDataSize);
IDB_INTERPOSE(IDBAudioObjectHasProperty, AudioObjectHasProperty);
IDB_INTERPOSE(IDBAudioObjectAddPropertyListener, AudioObjectAddPropertyListener);
IDB_INTERPOSE(IDBAudioObjectAddPropertyListenerBlock, AudioObjectAddPropertyListenerBlock);
