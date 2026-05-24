#pragma once

/* Declares the minimal freestanding diagnostic output ABI for Nim runtime support. */

#ifndef RKC_SIZE_T_DEFINED
#define RKC_SIZE_T_DEFINED
typedef __SIZE_TYPE__ size_t;
#endif

typedef struct RkcFile FILE;

extern FILE *stderr;

size_t fwrite(const void *ptr, size_t size, size_t count, FILE *stream);
int fflush(FILE *stream);
