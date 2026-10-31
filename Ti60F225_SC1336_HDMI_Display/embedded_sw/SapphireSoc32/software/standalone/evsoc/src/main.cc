// Gray binary-edge digits. The camera and display stay under RTL control.
#if defined(__riscv) && (__riscv_xlen != 32)
#error "TinyML library and this application require the RV32 SapphireSoC BSP"
#endif
#include <stdint.h>
#include <math.h>
#include "bsp.h"
#include "platform/vision/gray_digit_port.h"
#include "platform/vision/gray_digit_cache.h"
#include "platform/vision/gray_digit_track.h"
#include "tensorflow/lite/micro/all_ops_resolver.h"
#include "tensorflow/lite/micro/micro_error_reporter.h"
#include "tensorflow/lite/micro/micro_interpreter.h"
#include "tensorflow/lite/micro/debug_log.h"
#include "tensorflow/lite/schema/schema_generated.h"
#include "model/digits_int8_model_data.h"
#include "model/digit_selftest.h"
extern "C" {
struct GrayDigitStatus {
 uint32_t magic,version,stage,error,inferences,frame_id,box_count;
 uint32_t sequence,epoch,flags,published,rejected,candidates,last_label,last_score;
 uint32_t selftest_passed,selftest_max_difference;
};
volatile GrayDigitStatus gray_digit_status={0x47445331,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
struct GrayDigitPerf {
 uint32_t magic,version,tick_hz,frames,snapshot_ticks,locate_ticks,normalize_ticks;
 uint32_t inference_ticks,publish_ticks,total_ticks,max_total_ticks,candidates,invokes;
 uint32_t cache_hits,retarget_ticks,retarget_matched,stale_dropped;
};
volatile GrayDigitPerf gray_digit_perf={0x47445031,2,SYSTEM_CLINT_HZ,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
}
namespace {
using namespace gray_digit;
uint32_t ticks(){return uint32_t(clint_getTime(BSP_CLINT));}
alignas(64) uint8_t tensor_arena[256*1024];
alignas(64) uint32_t bitmap[kWords];
Detector detector;Box boxes[kMaxBoxes];
PredictionCache prediction_cache;
Tracker tracker;
tflite::MicroInterpreter* interpreter=nullptr;
TfLiteTensor* input=nullptr;TfLiteTensor* output=nullptr;
bool model_ready=false,initialization_attempted=false;
bool initialize_model(){
 if(initialization_attempted)return model_ready;
 initialization_attempted=true;if(!digit_accelerator_init())return false;
 flatbuffers::Verifier verify(digits_int8_model_data,digits_int8_model_data_len);
 if(!tflite::VerifyModelBuffer(verify))return false;
 const tflite::Model* model=tflite::GetModel(digits_int8_model_data);
 if(model->version()!=TFLITE_SCHEMA_VERSION)return false;
 static tflite::MicroErrorReporter reporter;static tflite::AllOpsResolver resolver;
 static tflite::MicroInterpreter instance(model,resolver,tensor_arena,sizeof(tensor_arena),&reporter);
 interpreter=&instance;
 if(instance.AllocateTensors()!=kTfLiteOk||instance.inputs_size()!=1||instance.outputs_size()!=1)return false;
 input=instance.input(0);output=instance.output(0);
 if(!input||!output||input->type!=kTfLiteInt8||output->type!=kTfLiteInt8||input->bytes!=1024||output->bytes!=11||
    input->dims->size!=4||input->dims->data[0]!=1||input->dims->data[1]!=32||input->dims->data[2]!=32||input->dims->data[3]!=1||
    input->params.zero_point!=-128||fabsf(input->params.scale-1.0f/255)>0.000001f||!(output->params.scale>0))return false;
 gray_digit_status.stage=6;
 for(unsigned t=0;t<10;++t){
  memcpy(input->data.int8,digit_test_inputs[t],1024);
  if(instance.Invoke()!=kTfLiteOk)return false;
  int best=-129;unsigned label=10;
  for(unsigned j=0;j<11;++j){
   int value=output->data.int8[j],diff=value-digit_test_outputs[t][j];if(diff<0)diff=-diff;
   if(unsigned(diff)>gray_digit_status.selftest_max_difference)gray_digit_status.selftest_max_difference=diff;
   if(value>best){best=value;label=j;}
  }
  gray_digit_status.last_label=label;
  if(label!=t||gray_digit_status.selftest_max_difference>4)return false;
  ++gray_digit_status.selftest_passed;
 }
 model_ready=true;MicroPrintf("gray: INT8 edge-digit model ready, 10 hardware self-tests passed\r\n");return true;
}
bool current(const VideoState& expected){VideoState s;return digit_state(&s)&&s.same(expected);}
bool publish_tracks(const VideoState& request){
 unsigned count=tracker.output(boxes,output->params.zero_point,output->params.scale);
 gray_digit_status.box_count=count;gray_digit_status.stage=7;
 if(digit_publish(boxes,count,request)){++gray_digit_status.published;return true;}
 ++gray_digit_status.rejected;digit_clear();return false;
}
}
int main(){
 uintptr_t hart;asm volatile("csrr %0, mhartid":"=r"(hart));if(hart)for(;;)asm volatile("wfi");
 gray_digit_status.stage=1;
 if(!digit_video_init()){gray_digit_status.error=1;gray_digit_status.stage=8;for(;;)asm volatile("nop");}
 digit_clear();VideoState previous={};bool was_enabled=false,pending=false;
 uint32_t before=0,capture_started=0,previous_update=0,infer_ticks=0,invokes=0,cache_hits=0;
 MicroPrintf("gray: fresh-frame digit boxes; hold K2 in FULL BINARY to toggle\r\n");
 for(;;){
  VideoState request;
  if(!digit_state(&request)){gray_digit_status.stage=2;continue;}
  gray_digit_status.flags=request.display_mode|(request.replay?4u:0u)|(request.requested?8u:0u);
  gray_digit_status.sequence=request.sequence;gray_digit_status.epoch=request.epoch;
  if(was_enabled!=request.enabled()||previous.sequence!=request.sequence||previous.epoch!=request.epoch){
   digit_clear();prediction_cache.clear();tracker.clear();pending=false;previous_update=0;infer_ticks=0;invokes=0;cache_hits=0;
  }
  previous=request;was_enabled=request.enabled();
  if(!request.enabled()){gray_digit_status.stage=2;continue;}
  if(!initialize_model()){gray_digit_status.error=2;gray_digit_status.stage=8;continue;}
  gray_digit_status.error=0;
  if(!pending){
   if(!digit_snapshot_start(&before,request)){gray_digit_status.stage=4;continue;}
   pending=true;capture_started=ticks();
  }
  uint32_t frame=0,first_started=0,snapshot_ticks=0,locate_ticks=0,track_ticks=0;
  int ready=digit_snapshot_poll(before,bitmap,&frame,request);
  if(ready<0){pending=false;tracker.clear();digit_clear();++gray_digit_status.rejected;continue;}
  if(ready>0){
   first_started=capture_started;snapshot_ticks=ticks()-capture_started;
   pending=false;
   // CPU now owns its private copy. Capture the next frame while this one is
   // located/classified; never read the FPGA buffer while it is being written.
   if(digit_snapshot_start(&before,request)){pending=true;capture_started=ticks();}
   gray_digit_status.frame_id=frame;gray_digit_status.stage=5;
   uint32_t phase=ticks();unsigned nc=detector.locate(bitmap);
   locate_ticks=ticks()-phase;phase=ticks();
   tracker.update(detector.candidates,nc,bitmap);gray_digit_status.candidates=nc;
   // Identical inputs need no new inference, including identical reject inputs.
   for(unsigned i=0;i<tracker.count;++i)if(!tracker.tracks[i].exact){
    tracker.tracks[i].pattern.unpack(input->data.int8);
    if(prediction_cache.lookup(input->data.int8,output->data.int8)){tracker.classify(i,output->data.int8);++cache_hits;}
   }
   track_ticks=ticks()-phase;
  }else if(ticks()-capture_started>SYSTEM_CLINT_HZ/2){
   // Never leave old detections on screen if the image source stops delivering.
   digit_clear();tracker.clear();pending=false;++gray_digit_status.rejected;continue;
  }
  // Repair a small number of lost/new identities BEFORE publishing the new
  // frame. Do not briefly publish an incomplete batch between CNN calls.
  // Steady tracking uses two calls; acquisition/repair is bounded at four.
  unsigned budget=ready>0?tracker.work_budget():1;bool changed=false,failed=false;
  for(unsigned pass=0;pass<budget;++pass){
  int index=tracker.next();
  if(index<0)break;
  tracker.tracks[index].pattern.unpack(input->data.int8);gray_digit_status.stage=6;
  uint32_t phase=ticks();
  if(prediction_cache.lookup(input->data.int8,output->data.int8)){++cache_hits;}
  else {
   if(interpreter->Invoke()!=kTfLiteOk){gray_digit_status.error=4;tracker.clear();digit_clear();failed=true;break;}
   prediction_cache.store(output->data.int8);++invokes;++gray_digit_status.inferences;
  }
  infer_ticks+=ticks()-phase;
  if(!current(request)){tracker.clear();digit_clear();pending=false;++gray_digit_status.rejected;failed=true;break;}
  tracker.classify(unsigned(index),output->data.int8);
  int best=-129;unsigned label=10;
  for(unsigned j=0;j<11;++j)if(output->data.int8[j]>best){best=output->data.int8[j];label=j;}
  gray_digit_status.last_label=label;
  gray_digit_status.last_score=uint32_t((best-output->params.zero_point)*output->params.scale*1000);
  changed=true;
  }
  if(failed)continue;
  if(ready>0||changed){
   uint32_t phase=ticks();
   if(!publish_tracks(request)){tracker.clear();pending=false;continue;}
   uint32_t now=ticks();
   if(ready>0){
    gray_digit_perf.publish_ticks=now-phase;gray_digit_perf.snapshot_ticks=snapshot_ticks;
    gray_digit_perf.locate_ticks=locate_ticks;gray_digit_perf.normalize_ticks=0;
    gray_digit_perf.inference_ticks=infer_ticks;gray_digit_perf.invokes=invokes;gray_digit_perf.cache_hits=cache_hits;
    gray_digit_perf.candidates=tracker.count;gray_digit_perf.retarget_ticks=track_ticks;
    gray_digit_perf.retarget_matched=tracker.matched;gray_digit_perf.stale_dropped=tracker.dropped;
    // Version 2 measures complete fresh-coordinate publications. Capture
    // overlaps processing; its duration is not additive with CPU phases.
    gray_digit_perf.total_ticks=now-(previous_update?previous_update:first_started);
    if(gray_digit_perf.total_ticks>gray_digit_perf.max_total_ticks)gray_digit_perf.max_total_ticks=gray_digit_perf.total_ticks;
    previous_update=now;++gray_digit_perf.frames;infer_ticks=0;invokes=0;cache_hits=0;
   }
  }else gray_digit_status.stage=4;
 }
}
