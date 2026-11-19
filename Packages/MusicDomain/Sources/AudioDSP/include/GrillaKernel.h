#ifndef GRILLA_KERNEL_H
#define GRILLA_KERNEL_H
#include <stdint.h>
#include "GrillaMIDI.h"
#ifdef __cplusplus
extern "C" {
#endif
typedef struct LGKernel LGKernel;
typedef struct LGSampleBank LGSampleBank;
typedef struct {int32_t pitch,offset,frames,loopStart;} LGSampleZone;
// Preparation and release are control-thread operations. Audio snapshots
// retain independent references to immutable sample banks.
LGSampleBank *lg_sample_create(int32_t rate,const LGSampleZone *zones,int32_t zoneCount,const int16_t *pcm,int32_t frameCount);
LGSampleBank *lg_sample_create_with_release(int32_t rate,const LGSampleZone *zones,int32_t zoneCount,const int16_t *pcm,int32_t frameCount,int32_t ringsOut);
void lg_sample_release(LGSampleBank *bank);
int lg_sha256(const uint8_t *data, int32_t count, char *hex);
typedef struct { int32_t tick, duration, pitch, velocity, track, pad, instrument; } LGNote;
typedef struct {float gainDB,pan;int32_t audible;} LGTrackMix;
// identity is stable, nonzero and unique within a project; presetVersion is
// legacy 1, Classic 2, Warm 3 or Bright 4 (persisted with schema 11),
// instrument is harmony/drums/bass/melody (0...3), midiChannel is 0...15.
typedef struct {LGTrackMix mix;int32_t presetVersion,instrument,midiChannel;uint64_t identity;} LGProjectTrack;
typedef struct { uint64_t frame; int32_t epoch,kind,track,a,b,token; float value; } LGPerformanceEvent;
typedef struct {
    uint64_t epoch,callbacks,comparedCallbacks;
    uint64_t maxExcessNanoseconds,maxIntervalNanoseconds,baselineBufferNanoseconds;
    uint64_t nonIncreasingTimestamps,clockRateChanges;
    uint32_t baselineFrames,inheritedAnchor;
} LGOutputTiming;
LGKernel *lg_create(double sampleRate);
void lg_destroy(LGKernel *k);
int lg_submit(LGKernel *k, const LGNote *notes, int count, double bpm, int start, int end, int loop, int revision);
// A live arrangement transaction. Notes, mixer, presets and FX are adopted at
// the same musical boundary. layoutToken must change when ordered track IDs
// change; this releases old-index live MIDI/sustain and crossfades in stereo.
// Publication has one serialized control-thread owner. A seek or stopped
// transport adopts immediately; playback keeps its tick and sample clock.
int lg_submit_project(LGKernel *k,const LGNote *notes,int count,double bpm,int start,int end,int loop,int revision,uint64_t layoutToken,const LGProjectTrack *tracks,int trackCount,float masterDB,float filter,float delayWet);
// Routes are fixed-size arrays of 8 track and 16 pad bank handles (or NULL).
int lg_submit_project_samples(LGKernel *k,const LGNote *notes,int count,double bpm,int start,int end,int loop,int revision,uint64_t layoutToken,const LGProjectTrack *tracks,int trackCount,float masterDB,float filter,float delayWet,LGSampleBank *const *instruments,LGSampleBank *const *pads);
int lg_submit_samples(LGKernel *k,const LGNote *notes,int count,double bpm,int start,int end,int loop,int revision,LGSampleBank *const *instruments,LGSampleBank *const *pads);
// On the serialized publication/control thread, copy up to three slot revision
// IDs. Retain routing metadata for these generations until the next publication;
// a concurrent audio handover cannot hide its generation from this bounded set.
int lg_snapshot_generations(LGKernel *k,int32_t *revisions,int capacity);
// 4 bands for each of 8 tracks followed by the master. 0 bypass, 1 peak,
 // 2 low shelf, 3 high shelf, 4 high pass, 5 low pass.
typedef struct {int32_t kind;float frequency,gainDB,q;} LGEQBand;
int lg_submit_project_eq(LGKernel*,const LGNote*,int,double,int,int,int,int,uint64_t,const LGProjectTrack*,int,float,float,float,LGSampleBank *const *,LGSampleBank *const *,const LGEQBand*);
int lg_submit_samples_eq(LGKernel*,const LGNote*,int,double,int,int,int,int,LGSampleBank *const *,LGSampleBank *const *,const LGEQBand*);
int lg_mix_revision_eq(LGKernel*,const LGTrackMix*,int,float,float,float,int,const LGEQBand*);
double lg_eq_response(const LGEQBand*,double rate,double frequency);
void lg_countin(LGKernel *k, int frames);
int lg_countremaining(LGKernel *k);
void lg_play(LGKernel *k, int play);
void lg_restart(LGKernel *k);
void lg_seek(LGKernel *k, int tick);
int lg_pad(LGKernel *k, int pad, int velocity);
// I3 note repeat: while set, the pad retriggers on the transport grid every
// stepTicks (120, 160, 240, 320 or 480) after the current tick; with the
// transport stopped it free-runs at the current tempo. pad -1 stops.
int lg_pad_repeat(LGKernel *k, int pad, int stepTicks, int velocity);
// I82: send MIDI clock (24 PPQN) with Start/Continue (+ Song Position) and
// Stop to the selected MIDI output, sample-timed with the transport.
void lg_midi_clock_out(LGKernel *k, int enabled);
// I16: live pitch bend (-12...+12 semitones) and modulation (0...1 = vibrato
// up to ±0.5 semitone at 5.5 Hz) for the voices of the track with `identity`.
// Zero for both leaves every voice bit-identical.
void lg_pitch_bend(LGKernel *k, uint64_t identity, float semitones, float modulation);
// I15 live arpeggiator for the track with `identity`: up to 16 held pitches
// (in the order played), stepTicks 120/160/240/320/480, mode 0 up, 1 down,
// 2 up-down, 3 as played, over 1...3 octaves. The first note sounds at once;
// later notes follow the transport grid (free-running when stopped). Updating
// the held notes keeps the timing; count 0 stops.
int lg_arp(LGKernel *k, uint64_t identity, const int32_t *pitches, int count, int stepTicks, int mode, int octaves, int velocity);
void lg_preview(LGKernel *k, int pitch);
void lg_note_preview(LGKernel *k, int pitch, int track, int instrument);
// Resolve a stable LGProjectTrack identity after audio-boundary adoption.
// Deleted/absent tracks are ignored rather than playing through a reused index.
int lg_note_preview_track(LGKernel *k,int pitch,uint64_t identity);
void lg_mix(LGKernel *k, int track, float db, float pan, int audible);
// Publish a complete mixer transaction; the audio callback adopts it once at a
// buffer boundary. Individual setters remain available for paused/offline setup.
int lg_mix_snapshot(LGKernel *k,const LGTrackMix *tracks,int count,float masterDB,float filter,float delayWet);
// Stage a mixer update for an exact lg_submit[_project] musical generation.
// Future-generation updates wait; stale-generation updates are discarded.
int lg_mix_snapshot_for_revision(LGKernel *k,const LGTrackMix *tracks,int count,float masterDB,float filter,float delayWet,int revision);
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
// I10: metronome level (-24...+6 dB), downbeat accent (0/1) and sound
// (0 beep, 1 high, 2 low). The defaults (0, 1, 0) are the original click.
// Applies to the count-in too. Returns 0 for invalid values.
int lg_metronome_config(LGKernel *k, float gainDB, int accent, int sound);
// Ideas I5, I56, I57, I59: per-track choke groups (0 = none; pads in the same
// group silence each other), sidechain ducking from the kick pad (0...12 dB),
// saturation drive (0...1) and bit depth (0 off, else 4...16); a master
// look-ahead limiter (ceiling -12...0 dBFS). All-zero tracks and a disabled
// limiter leave the output bit-identical. Index order follows the project
// tracks; values are adopted at the next sample. Returns 0 if invalid.
// reverbSend (0...1, I58) feeds a shared room reverb returned to the master.
typedef struct { int32_t choke[16]; float sidechainDB, drive; int32_t crushBits; float reverbSend; } LGTrackDynamics;
int lg_dynamics(LGKernel *k, const LGTrackDynamics *tracks, int count, int limiter, float ceilingDB);
// Frames of look-ahead delay the limiter adds while enabled (0 when off).
int lg_limiter_latency(LGKernel *k);
void lg_render(LGKernel *k, float *left, float *right, int frames);
void lg_render_midi(LGKernel *k,LGMIDIHub *hub,uint64_t hostTime,double hostTicksPerSecond,float *left,float *right,int frames);
// Serialized control owner: request a fresh measurement, adopted by the next
// valid host-timestamped output callback. The previous callback anchor survives
// epoch changes, so a first post-restart gap is included. Zero-host offline
// rendering is ignored. Wait until read.epoch matches the returned nonzero ID.
uint64_t lg_output_timing_begin(LGKernel *k);
// Bounded coherent read; returns 0 if busy/invalid and leaves *timing untouched.
// Excess is callback spacing minus the PREVIOUS callback's frame duration.
// baselineFrames/baselineBufferNanoseconds describe that initial expected span;
// inheritedAnchor indicates whether the epoch retained a prior real callback.
// These timestamp diagnostics do not prove physical output has no dropouts.
int lg_output_timing_read(LGKernel *k,LGOutputTiming *timing);
double lg_tick(LGKernel *k);
uint64_t lg_clock(LGKernel *k);
int lg_playing(LGKernel *k);
int lg_revision(LGKernel *k);
float lg_meter(LGKernel *k, int track);
// I63: copy the latest `count` (<= 4096) mono master samples for a spectrum
// view. Lock-free; a concurrent block may tear the copy, which only affects
// the picture. Returns the number of samples written.
int lg_scope_read(LGKernel *k, float *out, int count);
int lg_overflows(LGKernel *k);
#ifdef __cplusplus
}
#endif
#endif
