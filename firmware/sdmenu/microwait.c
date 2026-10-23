#include <stdint.h>

void microwait(int us)
{
  /* 25 MHz core, addi+bnez take about 6 cycles. Five loops ≈ 1 us. */
  int n = us * 5;
  if (n <= 0)
    return;
  __asm__ volatile (
    "1: addi %0, %0, -1\n"
    "bnez %0, 1b\n"
    : "+r"(n)
  );
}

void wait_cycles(int cycles)
{
  volatile int n = cycles;
  while (n--)
    ;
}
