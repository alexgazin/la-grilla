#ifndef GRILLA_KERNEL_H
#define GRILLA_KERNEL_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct LGKernel LGKernel;
int lg_sha256(const uint8_t *data, int32_t count, char *hex);
typedef struct { int32_t tick, duration, pitch, velocity, track, pad, instrument; } LGNote;
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
void lg_master(LGKernel *k, float db);
void lg_tail_on_end(LGKernel *k, int enabled);
void lg_metronome(LGKernel *k, int enabled);
void lg_render(LGKernel *k, float *left, float *right, int frames);
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
