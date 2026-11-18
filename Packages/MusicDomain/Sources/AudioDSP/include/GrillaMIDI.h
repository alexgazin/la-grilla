#ifndef GRILLA_MIDI_H
#define GRILLA_MIDI_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct LGMIDIHub LGMIDIHub;
typedef struct {uint64_t hostTime;int32_t source,status,channel,a,b,track,instrument;} LGMIDIEvent;
typedef struct {uint64_t hostTime;uint32_t epoch;int32_t status,a,b;} LGMIDIOutput;
LGMIDIHub *lg_midi_create(void);
void lg_midi_destroy(LGMIDIHub *hub);
// A connection handle includes its generation in the high bits and a slot 0...15
// in its low byte. Old callbacks cannot play through a reused slot.
void lg_midi_configure(LGMIDIHub *hub,uint32_t handle,int track,int instrument,int channelMask);
// Project-aware input binding. Identity uses the same stable nonzero key as
// LGProjectTrack; its current index/instrument is resolved at audio adoption.
// Configuration functions have one serialized control-thread owner.
void lg_midi_configure_track(LGMIDIHub *hub,uint32_t handle,uint64_t identity,int track,int instrument,int channelMask);
// The built-in keybed has its own listening level before the track mixer.
void lg_midi_configure_keyboard(LGMIDIHub *hub,uint32_t handle,uint64_t identity,int track,int instrument);
void lg_midi_disconnect(LGMIDIHub *hub,int slot);
int lg_midi_push(LGMIDIHub *hub,uint32_t handle,uint64_t hostTime,const uint8_t *bytes,int count);
int lg_midi_monitor_pop(LGMIDIHub *hub,LGMIDIEvent *events,int capacity);
uint64_t lg_midi_late(LGMIDIHub *hub);
uint64_t lg_midi_dropped(LGMIDIHub *hub);
int lg_midi_connected(LGMIDIHub *hub,uint32_t handle);
void lg_midi_input_overflow(LGMIDIHub *hub,uint32_t handle);
uint32_t lg_midi_output_configure(LGMIDIHub *hub,const int32_t *channels,int count,int enabled);
// Complete asynchronous endpoint selection only if its disabled generation is
// still current. A newer selection or None cannot be re-enabled by old work.
uint32_t lg_midi_output_activate(LGMIDIHub *hub,uint32_t generation,const int32_t *channels,int count,int enabled);
// Zero means disabled; otherwise the currently enabled destination generation.
uint32_t lg_midi_output_active_epoch(LGMIDIHub *hub);
int lg_midi_output_pop(LGMIDIHub *hub,LGMIDIOutput *events,int capacity);
int lg_midi_output_error(LGMIDIHub *hub);
void lg_midi_output_failed(LGMIDIHub *hub,int error);
void lg_midi_output_sent(LGMIDIHub *hub,int count);
uint64_t lg_midi_output_count(LGMIDIHub *hub);
// A separate, unattached hub can inspect a virtual QA destination on its control
// thread. Never call this on the hub consumed by an active audio renderer.
int lg_midi_probe_pop(LGMIDIHub *hub,LGMIDIEvent *events,int capacity);
#ifdef __cplusplus
}
#endif
#endif
