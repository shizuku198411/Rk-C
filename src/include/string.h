#pragma once

typedef __SIZE_TYPE__ size_t;

void *memset(void *s, int c, size_t n);
void *memcpy(void *dest, void *src, size_t n);
void *memmove(void *dest, void *src, size_t n);
int memcmp(void *s1, void *s2, size_t n);
int strcmp(char *s1, char *s2);
size_t strlen(char *s);
