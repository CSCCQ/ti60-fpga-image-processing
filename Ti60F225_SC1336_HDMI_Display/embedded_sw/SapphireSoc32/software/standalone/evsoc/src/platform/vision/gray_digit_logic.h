#ifndef GRAY_DIGIT_LOGIC_H
#define GRAY_DIGIT_LOGIC_H
#include <stdint.h>
#include <string.h>
namespace gray_digit {
constexpr unsigned kWidth=320, kHeight=180, kWords=kWidth*kHeight/32;
constexpr unsigned kMaxBoxes=16, kCandidates=64;
struct VideoState {
 uint32_t display_mode,sequence,epoch;bool replay,requested;
 bool enabled() const {return display_mode==1 && requested;}
 bool same(const VideoState& b) const {return enabled()&&b.enabled()&&sequence==b.sequence&&epoch==b.epoch&&replay==b.replay;}
};
struct Box {uint16_t x0,y0,x1,y1;uint8_t label;};
inline bool bit(const uint32_t* p,unsigned x,unsigned y) {unsigned i=y*kWidth+x;return (p[i>>5]>>(i&31))&1u;}
struct Detector {
 uint32_t remaining[kWords];uint16_t queue[kWidth*kHeight];
 Box candidates[kCandidates];unsigned count;
 unsigned locate(const uint32_t* p) {
  count=0;
  // Exactly the same clipped 3x3 dilation as nearby(), computed 32 pixels
  // at a time. remaining doubles as the visited map; clear before enqueue.
  const unsigned stride=kWidth/32;
  for(unsigned y=0;y<kHeight;++y)for(unsigned w=0;w<stride;++w){
   unsigned at=y*stride+w;uint32_t center=p[at],left=w?p[at-1]:0,right=w+1<stride?p[at+1]:0;
   if(y){center|=p[at-stride];if(w)left|=p[at-stride-1];if(w+1<stride)right|=p[at-stride+1];}
   if(y+1<kHeight){center|=p[at+stride];if(w)left|=p[at+stride-1];if(w+1<stride)right|=p[at+stride+1];}
   remaining[at]=center|(center<<1)|(center>>1)|(left>>31)|(right<<31);
  }
  // Starting at the lowest remaining bit preserves the original row-major
  // component order, including the original 64-candidate limit and tie order.
  for(unsigned word=0;word<kWords;++word)while(remaining[word]) {
   unsigned start=word*32+unsigned(__builtin_ctz(remaining[word]));
   remaining[word]&=~(1u<<(start&31));
   unsigned head=0,tail=0;queue[tail++]=start;
   unsigned x0=kWidth,y0=kHeight,x1=0,y1=0,pixels=0;
   while(head<tail) {
    unsigned n=queue[head++],xx=n%kWidth,yy=n/kWidth;
    if(bit(p,xx,yy)){if(xx<x0)x0=xx;if(xx>x1)x1=xx;if(yy<y0)y0=yy;if(yy>y1)y1=yy;++pixels;}
    for(int dy=-1;dy<=1;++dy) for(int dx=-1;dx<=1;++dx) {
     int nx=int(xx)+dx,ny=int(yy)+dy;
     if(nx<0||nx>=int(kWidth)||ny<0||ny>=int(kHeight))continue;
     unsigned at=ny*kWidth+nx;
     uint32_t mask=1u<<(at&31);
     if(remaining[at>>5]&mask){remaining[at>>5]&=~mask;queue[tail++]=at;}
    }
   }
   if(!pixels)continue;
   unsigned w=x1-x0+1,h=y1-y0+1;
   if(h<10||h>165||w<2||w>h*3/2||pixels<12)continue;
   if(count<kCandidates)candidates[count++]={uint16_t(x0),uint16_t(y0),uint16_t(x1),uint16_t(y1),0};
  }
  // Outer digit contours first. Nested holes are suppressed only AFTER a digit
  // passes classification, so a rejected paper border cannot hide its digits.
  for(unsigned i=1;i<count;++i){Box b=candidates[i];unsigned j=i;
   unsigned area=(b.x1-b.x0+1)*(b.y1-b.y0+1);
   while(j && unsigned((candidates[j-1].x1-candidates[j-1].x0+1)*(candidates[j-1].y1-candidates[j-1].y0+1))<area){candidates[j]=candidates[j-1];--j;}
   candidates[j]=b;
  }return count;
 }
};
inline void normalize(const uint32_t* p,const Box& b,int8_t* output) {
 memset(output,0x80,32*32);
 unsigned w=b.x1-b.x0+1,h=b.y1-b.y0+1,m=w>h?w:h;
 unsigned dw=w*24/m,dh=h*24/m;if(!dw)dw=1;if(!dh)dh=1;
 unsigned ox=(32-dw)/2,oy=(32-dh)/2;
 uint8_t xmap[kWidth];
 for(unsigned x=0;x<w;++x)xmap[x]=uint8_t(ox+x*dw/w);
 for(unsigned y=b.y0;y<=b.y1;++y){
  unsigned row=(oy+(y-b.y0)*dh/h)*32;
  for(unsigned x=b.x0;x<=b.x1;++x)if(bit(p,x,y))output[row+xmap[x-b.x0]]=127;
 }
}
inline bool contained(const Box& a,const Box& b) {return a.x0>=b.x0&&a.y0>=b.y0&&a.x1<=b.x1&&a.y1<=b.y1;}
inline void reading_order(Box* boxes,unsigned count) {
 for(unsigned i=1;i<count;++i){Box b=boxes[i];unsigned j=i;
  while(j){const Box& a=boxes[j-1];int dy=int(b.y0)-a.y0;unsigned h=b.y1-b.y0+1;
   bool before=dy < -int(h/2)||(dy<int(h/2)&&dy>=-int(h/2)&&b.x0<a.x0);
   if(!before)break;boxes[j]=a;--j;
  }boxes[j]=b;
 }
}
}
#endif
