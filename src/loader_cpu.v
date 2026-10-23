`default_nettype none
/* Do not define NRV_IS_IO_ADDR. Quark only prefetches the next
   instruction on non-memory ops. With synchronous RAM, a store
   must take the wait state or the following instruction is the
   data just written. */
`include "../third_party/FemtoRV/RTL/PROCESSOR/utils.v"
`include "../third_party/FemtoRV/RTL/PROCESSOR/femtorv32_quark_bicycle.v"
`default_nettype wire
