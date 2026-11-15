#ifndef GRILLA_KERNEL_H
#define GRILLA_KERNEL_H
#include <stdint.h>
#include "GrillaMIDI.h"
#ifdef __cplusplus
extern "C" {
#endif
typedef struct LGKernel LGKernel;
int lg_sha256(const uint8_t *data, int32_t count, char *hex);
typedef struct { int32_t tick, duration, pitch, velocity, track, pad, instrument; } LGNote;
typedef struct {float gainDB,pan;int32_t audible;} LGTrackMix;
typedef struct { uint64_t frame; int32_t epoch,kind,track,a,b,token; float value; } LGPerformanceEvent;
LGKernel *lg_create(double sampleRate);
void lg_destroy(LGKernel *k);
int lg_submit(LGKernel *k, const LGNote *notes, int count, double bpm, int start, int end, int loop, int revision);
void lg_countin(LGKernel *k, int frames);
int lg_countremaining(LGKernel *k);
void lg_play(LGKernel *k, int play);
void lg_restart(LGKernel *k);
void lg_seek(LGKernel *k, int tick);
int lg_pad(LGKernel *k, int pad, int velocity);
void lg_preview(LGKernel *k, int pitch);
void lg_note_preview(LGKernel *k, int pitch, int track, int instrument);
void lg_mix(LGKernel *k, int track, float db, float pan, int audible);
// Publish a complete mixer transaction; the audio callback adopts it once at a
// buffer boundary. Individual setters remain available for paused/offline setup.
int lg_mix_snapshot(LGKernel *k,const LGTrackMix *tracks,int count,float masterDB,float filter,float delayWet);
uint64_t lg_mix_revision(LGKernel *k);
int lg_preset_version(LGKernel *k,int track,int version);
void lg_master(LGKernel *k, float db);
void lg_effects(LGKernel *k, float filter, float delayWet);
void lg_panic(LGKernel *k);
void lg_perform_begin(LGKernel *k, int token, int epoch, int recording, uint64_t limitFrames);
int lg_perform_replay_submit(LGKernel *k, const LGPerformanceEvent *events, int count, uint64_t durationFrames, int epoch);
uint64_t lg_perform_queue(LGKernel *k, int kind, float value, int start, int end, int token);
uint64_t lg_perform_ack(LGKernel *k);
int lg_perform_pop(LGKernel *k, LGPerformanceEvent *events, int capacity);
void lg_perform_record_stop(LGKernel *k);
int lg_perform_mode(LGKernel *k);
int lg_perform_recording(LGKernel *k);
int lg_perform_epoch(LGKernel *k);
int lg_perform_active_token(LGKernel *k);
int lg_perform_pending_token(LGKernel *k);
int lg_perform_repeat(LGKernel *k);
int lg_perform_error(LGKernel *k);
int lg_perform_warning(LGKernel *k);
uint64_t lg_perform_clock(LGKernel *k);
uint64_t lg_perform_duration(LGKernel *k);
void lg_perform_finalize_paused(LGKernel *k);
float lg_gain_target(LGKernel *k, int track);
float lg_pan_target(LGKernel *k, int track);
float lg_filter_target(LGKernel *k);
float lg_delay_target(LGKernel *k);
void lg_tail_on_end(LGKernel *k, int enabled);
void lg_metronome(LGKernel *k, int enabled);
void lg_render(LGKernel *k, float *left, float *right, int frames);
void lg_render_midi(LGKernel *k,LGMIDIHub *hub,uint64_t hostTime,double hostTicksPerSecond,float *left,float *right,int frames);
double lg_tick(LGKernel *k);
uint64_t lg_clock(LGKernel *k);
int lg_playing(LGKernel *k);
int lg_revision(LGKernel *k);
float lg_meter(LGKernel *k, int track);
int lg_overflows(LGKernel *k);
#ifdef __cplusplus
}
#endif
#endif
