#ifndef GRILLA_MIDI_H
#define GRILLA_MIDI_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct LGMIDIHub LGMIDIHub;
typedef struct {uint64_t hostTime;int32_t source,status,channel,a,b,track,instrument;} LGMIDIEvent;
LGMIDIHub *lg_midi_create(void);
void lg_midi_destroy(LGMIDIHub *hub);
// A connection handle includes its generation in the high bits and a slot 0...15
// in its low byte. Old callbacks cannot play through a reused slot.
void lg_midi_configure(LGMIDIHub *hub,uint32_t handle,int track,int instrument,int channelMask);
void lg_midi_disconnect(LGMIDIHub *hub,int slot);
int lg_midi_push(LGMIDIHub *hub,uint32_t handle,uint64_t hostTime,const uint8_t *bytes,int count);
int lg_midi_monitor_pop(LGMIDIHub *hub,LGMIDIEvent *events,int capacity);
uint64_t lg_midi_late(LGMIDIHub *hub);
uint64_t lg_midi_dropped(LGMIDIHub *hub);
#ifdef __cplusplus
}
#endif
#endif
