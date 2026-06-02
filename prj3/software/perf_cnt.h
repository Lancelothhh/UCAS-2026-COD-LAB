
#ifndef __PERF_CNT__
#define __PERF_CNT__

#ifdef __cplusplus
extern "C" {
#endif

typedef struct Result {
	int pass;
	unsigned long msec;
	unsigned long inst_cnt;
} Result;

void bench_prepare(Result *res);
void bench_done(Result *res);
unsigned long _inst_retired();

#endif
