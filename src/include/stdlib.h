#pragma once

/* Declares the minimal freestanding allocation and termination ABI for Nim runtime support. */

#ifndef RKC_SIZE_T_DEFINED
#define RKC_SIZE_T_DEFINED
typedef __SIZE_TYPE__ size_t;
#endif

void *malloc(size_t size);
void free(void *ptr);
void exit(int status);
