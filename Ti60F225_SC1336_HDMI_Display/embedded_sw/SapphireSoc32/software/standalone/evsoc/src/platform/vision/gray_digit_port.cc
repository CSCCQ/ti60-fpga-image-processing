#include "gray_digit_port.h"
#include "soc.h"
#include "platform/tinyml/accel_settings.h"
#include "platform/interrupt/intc.h"
namespace {
inline uint32_t rd(unsigned offset){return *reinterpret_cast<volatile uint32_t*>(IO_APB_SLAVE_1_INPUT+offset);}
inline void wr(unsigned offset,uint32_t value){*reinterpret_cast<volatile uint32_t*>(IO_APB_SLAVE_1_INPUT+offset)=value;}
}
bool digit_video_init(){return rd(0)==0x47525931u&&(rd(4)&0x76u)==0x76u&&rd(0x190)==((180u<<16)|320u);}
bool digit_state(gray_digit::VideoState* s){
 for(unsigned i=0;i<3;++i){uint32_t seq=rd(0xc),epoch=rd(0x10),v=rd(8);
  if(seq==rd(0xc)&&epoch==rd(0x10)){s->display_mode=v&3;s->sequence=seq;s->epoch=epoch;s->replay=v&4;s->requested=v&8;return true;}
 }return false;
}
void digit_clear(){wr(0x1c,0);wr(0x120,1);}
bool digit_snapshot_start(uint32_t* before,const gray_digit::VideoState& expected){
 gray_digit::VideoState now;
 if((rd(0x180)&1u)||!digit_state(&now)||!now.same(expected))return false;
 *before=rd(0x184);wr(0x180,1);return true;
}
int digit_snapshot_poll(uint32_t before,uint32_t* bitmap,uint32_t* id,const gray_digit::VideoState& expected){
 gray_digit::VideoState now;
 if(!digit_state(&now)||!now.same(expected))return -1;
 uint32_t done=rd(0x184);if(done==before)return 0;
 for(unsigned i=0;i<gray_digit::kWords;++i){wr(0x188,i);(void)rd(0x188);bitmap[i]=rd(0x18c);}
 *id=done;return digit_state(&now)&&now.same(expected)?1:-1;
}
bool digit_snapshot(uint32_t* bitmap,uint32_t* id,const gray_digit::VideoState& expected){
 gray_digit::VideoState current;
 for(unsigned n=0;rd(0x180)&1u;++n){
  if(n>1000000u||!digit_state(&current)||!current.same(expected))return false;
 }
 uint32_t before=rd(0x184);wr(0x180,1);
 for(unsigned n=0;rd(0x184)==before;++n){
  if(n>1000000u||!digit_state(&current)||!current.same(expected))return false;
 }
 *id=rd(0x184);
 for(unsigned i=0;i<gray_digit::kWords;++i){
  wr(0x188,i);
  // Synchronous BRAM read: one address readback before sampling the data.
  (void)rd(0x188);bitmap[i]=rd(0x18c);
 }
 return digit_state(&current)&&current.same(expected);
}
bool digit_publish(const gray_digit::Box* boxes,unsigned count,const gray_digit::VideoState& expected){
 gray_digit::VideoState now;
 if(count>gray_digit::kMaxBoxes||!digit_state(&now)||!now.same(expected))return false;
 // Sort only the published view. Tracker/cache order and caller data stay
 // unchanged; each label travels with its own coordinates, including repeats.
 unsigned order[gray_digit::kMaxBoxes];
 for(unsigned i=0;i<count;++i){unsigned j=i;
  while(j && boxes[order[j-1]].label>boxes[i].label){order[j]=order[j-1];--j;}
  order[j]=i;
 }
 wr(0x1c,count);
 for(unsigned i=0;i<count;++i){const gray_digit::Box& b=boxes[order[i]];unsigned off=0x20+i*16;
  wr(off,(uint32_t(b.label)<<16)|uint32_t(b.x0*4));wr(off+4,b.y0*4);
  wr(off+8,b.x1*4+3);wr(off+12,b.y1*4+3);
 }
 if(!digit_state(&now)||!now.same(expected)){digit_clear();return false;}
 wr(0x124,expected.sequence);wr(0x128,expected.epoch);wr(0x120,1);return true;
}
bool digit_accelerator_init(){
 if(!(rd(4)&4))return false;
 // GRAY_DMA_ACTIVE=0: keep FPGA camera/HDMI DDR ownership.
 dma_init();init_accel(0);return accel_count>0;
}
