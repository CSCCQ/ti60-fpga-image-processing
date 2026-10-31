#ifndef GRAY_DIGIT_TRACK_H
#define GRAY_DIGIT_TRACK_H
#include "gray_digit_logic.h"
namespace gray_digit {
inline unsigned popcount32(uint32_t v){v-=((v>>1)&0x55555555u);v=(v&0x33333333u)+((v>>2)&0x33333333u);v=(v+(v>>4))&0x0f0f0f0fu;return (v*0x01010101u)>>24;}
struct Pattern {
 uint32_t row[32];unsigned pixels;
 void pack(const int8_t* input){pixels=0;for(unsigned y=0;y<32;++y){uint32_t r=0;for(unsigned x=0;x<32;++x)if(input[y*32+x]==127)r|=1u<<x;row[y]=r;pixels+=popcount32(r);}}
 void unpack(int8_t* output)const{for(unsigned y=0;y<32;++y)for(unsigned x=0;x<32;++x)output[y*32+x]=(row[y]&(1u<<x))?127:-128;}
 bool same(const Pattern& b)const{return !memcmp(row,b.row,sizeof(row));}
 uint32_t dilated(unsigned y)const{uint32_t r=row[y];if(y)r|=row[y-1];if(y<31)r|=row[y+1];return r|(r<<1)|(r>>1);}
};
// Only a near-identical contour may inherit a recently verified label. The
// classifier still revisits changed inputs in round-robin order. Matching is
// checked against the verified pattern, preventing cumulative shape drift.
inline bool similar(const Pattern& a,const Pattern& b,unsigned* cost){
 if(!a.pixels||!b.pixels||a.pixels*4<b.pixels*3||b.pixels*4<a.pixels*3)return false;
 if(a.same(b)){*cost=0;return true;}
 unsigned missing_a=0,missing_b=0;
 for(unsigned y=0;y<32;++y){missing_a+=popcount32(a.row[y]&~b.dilated(y));missing_b+=popcount32(b.row[y]&~a.dilated(y));}
 // Native camera crops can change width by one pixel, making the 24-pixel
 // normalization grid move different strokes independently. Rigid overlap is
 // therefore unsuitable. Require almost every stroke to stay within one
 // pixel, AND preserve its spatial mass distribution (not dilation alone).
 if(missing_a*100>a.pixels*2+100||missing_b*100>b.pixels*2+100)return false;
 unsigned distribution=0;
 for(unsigned by=0;by<32;by+=8)for(unsigned bx=0;bx<32;bx+=8){
  unsigned ca=0,cb=0;for(unsigned y=by;y<by+8;++y){ca+=popcount32((a.row[y]>>bx)&255u);cb+=popcount32((b.row[y]>>bx)&255u);}
  int diff=int(ca*b.pixels)-int(cb*a.pixels);distribution+=unsigned(diff<0?-diff:diff);
 }
 if(distribution*100>a.pixels*b.pixels*22)return false;
 *cost=(missing_a+missing_b)*1024/(a.pixels+b.pixels)+distribution*256/(a.pixels*b.pixels);return true;
}
struct Track {
 Box box;Pattern pattern,verified_pattern;int8_t scores[11];
 uint32_t verified_at;bool classified,exact;
};
struct Tracker {
 static constexpr unsigned kHoldFrames=8;
 Track tracks[kCandidates],previous[kCandidates];unsigned count,frame,cursor,matched,dropped;
 void clear(){count=0;frame=0;cursor=0;matched=0;dropped=0;}
 void update(const Box* boxes,unsigned n,const uint32_t* bitmap){
  unsigned old_count=count;memcpy(previous,tracks,count*sizeof(Track));count=n;++frame;matched=0;dropped=0;
  bool used[kCandidates]={};int8_t input[1024];
  for(unsigned i=0;i<count;++i){
   Track& t=tracks[i];t.box=boxes[i];normalize(bitmap,t.box,input);t.pattern.pack(input);t.classified=false;t.exact=false;t.verified_at=0;
   unsigned best=kCandidates,best_cost=~0u,second=~0u;
   for(unsigned j=0;j<old_count;++j){
    const Track& o=previous[j];if(used[j]||!o.classified)continue;
    unsigned w=t.box.x1-t.box.x0+1,h=t.box.y1-t.box.y0+1,ow=o.box.x1-o.box.x0+1,oh=o.box.y1-o.box.y0+1;
    if(w*4<ow*3||ow*4<w*3||h*4<oh*3||oh*4<h*3)continue;
    int dx=int(t.box.x0+t.box.x1)-int(o.box.x0+o.box.x1),dy=int(t.box.y0+t.box.y1)-int(o.box.y0+o.box.y1);
    unsigned distance=unsigned(dx*dx+dy*dy),limit=(h>ow?h:ow)+16;
    if(distance>limit*limit)continue;
    unsigned shape=0;if(!similar(t.pattern,o.verified_pattern,&shape))continue;
    unsigned cost=shape*1024+distance;
    if(cost<best_cost){second=best_cost;best_cost=cost;best=j;}else if(cost<second)second=cost;
   }
   // Two equally plausible identities are left unclassified.
   if(best<old_count&&(second==~0u||second-best_cost>64)){
    const Track& o=previous[best];used[best]=true;
    t.verified_pattern=o.verified_pattern;t.verified_at=o.verified_at;memcpy(t.scores,o.scores,11);
    t.exact=t.pattern.same(t.verified_pattern);t.classified=t.exact||frame-t.verified_at<=kHoldFrames;
    if(t.exact)t.verified_at=frame;
    if(t.classified)++matched;else ++dropped;
   }
  }
  if(count)cursor%=count;else cursor=0;
 }
 int next(){
  // Recover missing labels first. Among tracked labels refresh the oldest
  // verification, because candidate area sorting can reorder every frame.
  unsigned best=count,age=0;
  for(unsigned step=0;step<count;++step){unsigned i=(cursor+step)%count;
   if(!tracks[i].classified){cursor=(i+1)%count;return int(i);}
   unsigned current_age=frame-tracks[i].verified_at;
   if(!tracks[i].exact&&(best==count||current_age>age)){best=i;age=current_age;}
  }
  if(best==count)return -1;cursor=(best+1)%count;return int(best);
 }
 unsigned work_budget()const{
  unsigned missing=0;for(unsigned i=0;i<count;++i)if(!tracks[i].classified)++missing;
  return missing>4?4:(missing>2?missing:2);
 }
 void classify(unsigned i,const int8_t* scores){Track& t=tracks[i];memcpy(t.scores,scores,11);t.verified_pattern=t.pattern;t.verified_at=frame;t.classified=true;t.exact=true;}
 unsigned output(Box* out,int zero,float scale)const{
  unsigned n=0;for(unsigned i=0;i<count&&n<kMaxBoxes;++i){const Track& t=tracks[i];if(!t.classified)continue;
   int best=-129,second=-129;unsigned label=10;
   for(unsigned j=0;j<11;++j){int v=t.scores[j];if(v>best){second=best;best=v;label=j;}else if(v>second)second=v;}
   if(label>=10||(best-zero)*scale<.85f||(best-second)*scale<.30f)continue;
   bool duplicate=false;for(unsigned j=0;j<n;++j)if(contained(t.box,out[j]))duplicate=true;
   if(!duplicate){out[n]=t.box;out[n++].label=label;}
  }reading_order(out,n);return n;
 }
};
}
#endif
