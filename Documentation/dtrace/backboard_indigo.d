/* vim: set tabstop=2 shiftwidth=2 filetype=dtrace: */
/* Tracing of Indigo Messages in backboardd */

#include <SimulatorApp/Mach.h>
#include <SimulatorApp/Indigo.h>
#include <SimulatorApp/Purple.h>

/* Store the reference to the header, so we can copy it when we return */
pid$target::mach_msg:entry
{
  self->head_ref = arg0;
}

/* Extract the mach_msg_header now we've returned */
pid$target::mach_msg:return
{
  self->header = (MachMessageHeader *) copyin(self->head_ref, sizeof(MachMessageHeader));
  self->indigo = (IndigoMessage *) NULL;
}

/* Extract the Indigo Message if appropriate */
pid$target::mach_msg:return
/ self->header->msgh_remote_port == 0 && self->header->msgh_id == 0 && self->header->msgh_size == 0xb0 /
{
  self->indigo = (IndigoMessage *) copyin(self->head_ref, sizeof(IndigoMessage));
  printf("Indigo Message on Port %d", self->header->msgh_local_port);
}

/* Print info about the Button, if a Button Press */
pid$target::mach_msg:return
/ self->indigo != NULL && self->indigo->eventType == IndigoEventTypeButton /
{
  printf("Button Press");
}
