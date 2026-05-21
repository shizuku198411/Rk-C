## Defines trap frame and trap-related kernel data structures.
import ../../lib/types

type
  TrapFrame* {.bycopy.} = object
    ra*: U64
    gp*: U64
    tp*: U64
    t0*: U64
    t1*: U64
    t2*: U64
    t3*: U64
    t4*: U64
    t5*: U64
    t6*: U64
    a0*: U64
    a1*: U64
    a2*: U64
    a3*: U64
    a4*: U64
    a5*: U64
    a6*: U64
    a7*: U64
    s0*: U64
    s1*: U64
    s2*: U64
    s3*: U64
    s4*: U64
    s5*: U64
    s6*: U64
    s7*: U64
    s8*: U64
    s9*: U64
    s10*: U64
    s11*: U64
    sp*: U64
    sepc*: U64
    sstatus*: U64
    reserved0*: U64
