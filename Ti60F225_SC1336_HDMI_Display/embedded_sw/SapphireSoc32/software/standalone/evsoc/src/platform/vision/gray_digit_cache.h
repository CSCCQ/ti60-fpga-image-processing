#ifndef GRAY_DIGIT_CACHE_H
#define GRAY_DIGIT_CACHE_H
#include <stdint.h>
#include <string.h>
namespace gray_digit {
// normalize() only emits -128/+127. Cache exact 1024-bit patterns, including
// reject outputs. A hash never substitutes for the full pattern comparison.
// Position is intentionally excluded: translating an identical crop must not
// force another CNN pass, and the box always uses the current snapshot.
struct PredictionCache {
 static constexpr unsigned kEntries=128;
 struct Entry {uint32_t hash,bits[32];int8_t scores[11];bool valid;};
 Entry entries[kEntries];unsigned next;uint32_t key[32],hash;
 void clear(){memset(entries,0,sizeof(entries));next=0;}
 bool lookup(const int8_t* input,int8_t* output){
  hash=2166136261u;
  for(unsigned y=0;y<32;++y){uint32_t row=0;
   for(unsigned x=0;x<32;++x)if(input[y*32+x]==127)row|=1u<<x;
   key[y]=row;hash=(hash^row)*16777619u;
  }
  for(unsigned i=0;i<kEntries;++i){const Entry& e=entries[i];
   if(e.valid&&e.hash==hash&&!memcmp(e.bits,key,sizeof(key))){memcpy(output,e.scores,11);return true;}
  }return false;
 }
 void store(const int8_t* output){
  Entry& e=entries[next];e.hash=hash;memcpy(e.bits,key,sizeof(key));memcpy(e.scores,output,11);e.valid=true;
  next=(next+1)%kEntries;
 }
};
}
#endif
