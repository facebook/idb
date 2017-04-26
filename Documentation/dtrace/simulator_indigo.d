/* vim: set tabstop=2 shiftwidth=2 filetype=dtrace: */
/* Tracing of Indigo and mach Messages in Simulator.app
 * Imports come from the Reversed C-Structs
 * #import <mach/mach.h> cannot be used as the dtrace preprocessor barfs on some macros.
 *
 * If self script is ran with -d PATH-TO-SIMULATOR-APP, you will be able to see the tracing of the
 * IndigoHIDRegistrationPort, followed by the handshake which establishes a reply-port.
 * Indigo Messages are then sent to self reply port.
 */

#include <SimulatorApp/Mach.h>
#include <SimulatorApp/Indigo.h>
#include <SimulatorApp/Purple.h>

dtrace:::BEGIN
{
  printf(
    "\nHeader=%d Purple=%d Indigo=%d",
    sizeof(MachMessageHeader),
    sizeof(PurpleMessage),
    sizeof(IndigoMessage)
  );
  printf(
    "\nu1=%d u2=%d u3=%d u4=%d u5=%d u6=%d",
    sizeof(IndigoDigitizerPayload),
    sizeof(IndigoUnknownPayload2),
    sizeof(IndigoButtonPayload),
    sizeof(IndigoUnknownPayload4),
    sizeof(IndigoUnknownPayload5),
    sizeof(IndigoUnknownPayload6)
  );
  printf(
    "\nHeader Offsets %x %x %x %x %x %x",
    offsetof(MachMessageHeader, msgh_bits),
    offsetof(MachMessageHeader, msgh_size),
    offsetof(MachMessageHeader, msgh_remote_port),
    offsetof(MachMessageHeader, msgh_local_port),
    offsetof(MachMessageHeader, msgh_voucher_port),
    offsetof(MachMessageHeader, msgh_id)
  );
  printf(
    "\nIndigo Offsets %x %x %x %x",
    offsetof(IndigoMessage, header),
    offsetof(IndigoMessage, innerSize),
    offsetof(IndigoMessage, eventType),
    offsetof(IndigoMessage, inner)
  );
  printf(
    "\nIndigo Payload Offsets %x %x %x %x",
    offsetof(IndigoInner, field1),
    offsetof(IndigoInner, timestamp),
    offsetof(IndigoInner, field3),
    offsetof(IndigoInner, unionPayload)
  );
  printf(
    "\nKeypress Offsets %x %x %x %x %x",
    offsetof(IndigoButtonPayload, eventSource),
    offsetof(IndigoButtonPayload, eventType),
    offsetof(IndigoButtonPayload, eventClass),
    offsetof(IndigoButtonPayload, keyCode),
    offsetof(IndigoButtonPayload, field5)
  );
  printf(
    "\nDigitizer Offsets %x %x %x %x %x",
    offsetof(IndigoDigitizerPayload, field1),
    offsetof(IndigoDigitizerPayload, field2),
    offsetof(IndigoDigitizerPayload, field3),
    offsetof(IndigoDigitizerPayload, xRatio),
    offsetof(IndigoDigitizerPayload, yRatio)
  );
  indigohid_registration_port = 0;
  indigohid_reply_port = 0;
}

/* Extract a reference to the port outparam when allocating the port */
pid$target::mach_port_allocate:entry
{
  self->port_ref = arg2
}

/* Read the reference out when the call returns */
pid$target::mach_port_allocate:return
{
  self->port = *((unsigned int *) copyin(self->port_ref, sizeof(unsigned int)));
}

/* Get the Port that is used to register */
objc$target:SimDevice:*registerPort*:entry
/ indigohid_registration_port == 0  /
{
  indigohid_registration_port = (unsigned int) arg2;
  printf("Registered IndigoHID %d", indigohid_registration_port);
  ustack();
}

/* Copy in the header passed to mach_msg. Also store the reference so it can be copied in the return */
pid$target::mach_msg:entry
{
  self->header_ref = arg0;
  self->header = (MachMessageHeader *) copyin(arg0, sizeof(MachMessageHeader));
}

/* If the local port matches the Indigo Registration Port, extract the reply port from the reference on return */
pid$target::mach_msg:return
/ indigohid_registration_port != 0 && self->header->msgh_local_port == indigohid_registration_port /
{
  self->header = (MachMessageHeader *) copyin(self->header_ref, sizeof(MachMessageHeader));
  printf("Reply Local %d Remote %d", self->header->msgh_local_port, self->header->msgh_remote_port);
  indigohid_reply_port = self->header->msgh_remote_port;
}

/* Extract the port for an insert_right */
pid$target::mach_port_insert_right:entry
{
  self->port = arg1;
}

/* Show the rights added in the indigohid_reply_port */
pid$target::mach_port_insert_right:entry
/ indigohid_reply_port != 0 && indigohid_reply_port == self->port /
{
  printf("Insert Right into Reply Port %d", self->port);
  ustack();
}

/* Extract the mach_msg_header. A send header is complete, so it can be copied on entry */
pid$target::mach_msg_send:entry
{
  self->header = (MachMessageHeader *) copyin(arg0, sizeof(MachMessageHeader));
  self->indigo = (IndigoMessage *) NULL;
  self->purple = (PurpleMessage *) NULL;
  self->buttonEventSource = (unsigned int *) NULL;
  self->buttonEventType = (unsigned int *) NULL;
  self->keyCode = (unsigned int *) NULL;
  self->touchDirection = (unsigned int *) NULL;
  self->touchX = (unsigned int *) NULL;
  self->touchY = (unsigned int *) NULL;
}

/* If it's an Indigo Message, copy the value in. */
pid$target::mach_msg_send:entry
/ indigohid_reply_port == self->header->msgh_remote_port || self->header->msgh_id == 0 /
{
  self->indigo = (IndigoMessage *) copyin(arg0, sizeof(IndigoMessage));
  printf("Indigo Message on Port %d", self->header->msgh_remote_port);
}

/* Extract the Purple Message if appropriate */
pid$target::mach_msg_send:entry
/ self->header->msgh_id > 0 /
{
  self->purple = (PurpleMessage *) copyin(arg0, sizeof(PurpleMessage));
  printf("Purple Message on Port %d", self->header->msgh_remote_port);
}

/* Extract the Button Press from the Indigo Message */
pid$target::mach_msg_send:entry
/ self->indigo != NULL && self->indigo->eventType == IndigoEventTypeButton /
{
  self->buttonEventSource = ((unsigned int *) (((uintptr_t) self->indigo) + ((uintptr_t) 0x30)));
  self->buttonEventType = ((unsigned int *) (((uintptr_t) self->indigo) + ((uintptr_t) 0x34)));
}

/* Extract the Touch from the Indigo Message */
pid$target::mach_msg_send:entry
/ self->indigo != NULL && self->indigo->eventType == IndigoEventTypeTouch /
{
  self->touchDirection = ((unsigned int *) (((uintptr_t) self->indigo) + ((uintptr_t) 0x64)));
  self->touchX = ((unsigned int *) (((uintptr_t) self->indigo) + ((uintptr_t) 0x3c)));
  self->touchY = ((unsigned int *) (((uintptr_t) self->indigo) + ((uintptr_t) 0x44)));
}

pid$target::mach_msg_send:entry
/ self->touchDirection != NULL && *(self->touchDirection) == 0x1 /
{
  printf("Touch Down %d %d", *self->touchX, *self->touchY)
}

pid$target::mach_msg_send:entry
/ self->touchDirection != NULL && *(self->touchDirection) == 0x0 /
{
  printf("Touch Up %d %d", *self->touchX, *self->touchY)
}

pid$target::mach_msg_send:entry
/ self->buttonEventSource != NULL && *(self->buttonEventSource) == ButtonEventSourceHomeButton && *(self->buttonEventType) == ButtonEventTypeDown /
{
  printf("Home Button Down");
}

pid$target::mach_msg_send:entry
/ self->buttonEventSource != NULL && *(self->buttonEventSource) == ButtonEventSourceHomeButton && *(self->buttonEventType) == ButtonEventTypeUp /
{
  printf("Home Button Up");
}

pid$target::mach_msg_send:entry
/ self->buttonEventSource != NULL && *(self->buttonEventSource) == ButtonEventSourceSideButton && *(self->buttonEventType) == ButtonEventTypeDown /
{
  printf("Lock Button Down");
}

pid$target::mach_msg_send:entry
/ self->buttonEventSource != NULL && *(self->buttonEventSource) == ButtonEventSourceSideButton && *(self->buttonEventType) == ButtonEventTypeUp /
{
  printf("Lock Button Up");
}

pid$target::mach_msg_send:entry
/ self->buttonEventSource != NULL && *(self->buttonEventSource) == ButtonEventSourceSiri && *(self->buttonEventType) == ButtonEventTypeDown /
{
  printf("Siri Button Down");
}

pid$target::mach_msg_send:entry
/ self->buttonEventSource != NULL && *(self->buttonEventSource) == ButtonEventSourceSiri && *(self->buttonEventType) == ButtonEventTypeUp /
{
  printf("Siri Button Up");
}

pid$target::mach_msg_send:entry
/ self->buttonEventSource != NULL && *(self->buttonEventSource) == ButtonEventSourceKeyboard /
{
  self->keyCode = ((unsigned int *) (((uintptr_t) self->indigo) + ((uintptr_t) 0x3c)));
}

pid$target::mach_msg_send:entry
/ self->keyCode != NULL && *(self->buttonEventType) == ButtonEventTypeDown /
{
  printf("Key %d Down", *(self->keyCode));
}

pid$target::mach_msg_send:entry
/ self->keyCode != NULL && *(self->buttonEventType) == ButtonEventTypeUp /
{
  printf("Key %d Up", *(self->keyCode));
}
