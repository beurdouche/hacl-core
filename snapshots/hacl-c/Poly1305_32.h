/* This file was auto-generated by KreMLin! */
#ifndef __Poly1305_32_H
#define __Poly1305_32_H



#include "kremlib.h"
#include "testlib.h"

typedef void *Hacl_MAC_Poly1305_32_log_t;

typedef uint32_t *Hacl_MAC_Poly1305_32_bigint;

typedef uint8_t *Hacl_MAC_Poly1305_32_uint8_p;

typedef uint32_t *Hacl_MAC_Poly1305_32_elemB;

typedef uint8_t *Hacl_MAC_Poly1305_32_wordB;

typedef uint8_t *Hacl_MAC_Poly1305_32_wordB_16;

typedef struct {
  uint32_t *x00;
  uint32_t *x01;
}
Hacl_MAC_Poly1305_32_poly1305_state;

void Poly1305_32_crypto_onetimeauth(uint8_t *output, uint8_t *input, uint64_t len, uint8_t *k);
#endif
