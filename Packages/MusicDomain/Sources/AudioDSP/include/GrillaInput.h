#ifndef GRILLA_INPUT_H
#define GRILLA_INPUT_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct LGInput LGInput;
typedef struct LGInputState {
    uint64_t frames;
    uint64_t firstHostTime;
    uint64_t lastHostTime;
    uint32_t queuedFrames;
    uint32_t overflow;
    uint32_t invalidInput;
    uint32_t finished;
    float peak;
} LGInputState;
/* Allocation happens only here. One producer/tap, one consumer/worker. */
LGInput *lg_input_create(double sampleRate,uint32_t capacity,uint64_t startHostTime,double hostTicksPerSecond,uint64_t frameLimit);
void lg_input_destroy(LGInput *input);
/* Arm a prepared tap once (create with startHostTime UINT64_MAX). */
int lg_input_arm(LGInput *input,uint64_t startHostTime);
/* Same one-time arm, with an actual capture limit <= the prepared maximum. */
int lg_input_arm_limit(LGInput *input,uint64_t startHostTime,uint64_t frameLimit);
/* Callback-safe: bounded copies/downmix, atomics; no allocation, lock or file I/O. */
uint32_t lg_input_push(LGInput *input,const void *channelPointers,uint32_t channelCount,uint32_t frames,int interleaved,uint64_t hostTime);
uint32_t lg_input_pop(LGInput *input,float *destination,uint32_t capacity);
void lg_input_close(LGInput *input);
LGInputState lg_input_state(const LGInput *input);
#ifdef __cplusplus
}
#endif
#endif
