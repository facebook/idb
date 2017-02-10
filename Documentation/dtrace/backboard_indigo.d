/* vim: set tabstop=2 shiftwidth=2 filetype=dtrace: */
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
