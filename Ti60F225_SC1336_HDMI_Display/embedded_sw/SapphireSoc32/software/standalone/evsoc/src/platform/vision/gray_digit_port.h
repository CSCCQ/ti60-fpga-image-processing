#ifndef GRAY_DIGIT_PORT_H
#define GRAY_DIGIT_PORT_H
#include "gray_digit_logic.h"
bool digit_video_init();
bool digit_state(gray_digit::VideoState* state);
bool digit_snapshot(uint32_t* bitmap,uint32_t* frame_id,const gray_digit::VideoState& expected);
bool digit_snapshot_start(uint32_t* before,const gray_digit::VideoState& expected);
int digit_snapshot_poll(uint32_t before,uint32_t* bitmap,uint32_t* frame_id,const gray_digit::VideoState& expected);
bool digit_publish(const gray_digit::Box* boxes,unsigned count,const gray_digit::VideoState& expected);
void digit_clear();
bool digit_accelerator_init();
#endif
