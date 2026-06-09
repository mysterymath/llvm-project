# REQUIRES: x86
# RUN: rm -rf %t && split-file %s %t && cd %t
# RUN: llvm-mc -filetype=obj -triple=x86_64-pc-linux asm.s -o asm.o
# RUN: llvm-mc -filetype=obj -triple=x86_64-pc-linux nodwarf.s -o nodwarf.o

## Case 1: Profile-guided spilling (cold_func spills to FLASH, hot_func stays in RAM)
# RUN: ld.lld -T spill.ld asm.o -o out1 --spill-coldest-first --irpgo-profile=profile.prof --enable-non-contiguous-regions
# RUN: llvm-readelf -S out1 | FileCheck %s --check-prefix=CASE1

# CASE1:      .text       PROGBITS 0000000000000000 {{.*}} 000004
# CASE1-NEXT: .text_spill PROGBITS 0000000000001000 {{.*}} 000004

## Case 2: Stable tie-breaking fallback for equal sample counts (both 0)
# RUN: ld.lld -T spill.ld asm.o -o out2 --spill-coldest-first --irpgo-profile=empty.prof --enable-non-contiguous-regions
# RUN: llvm-readelf -S out2 | FileCheck %s --check-prefix=CASE2

# CASE2:      .text       PROGBITS 0000000000000000 {{.*}} 000004
# CASE2-NEXT: .text_spill PROGBITS 0000000000001000 {{.*}} 000004

## Case 3: Symbol table fallback for functions without DWARF
# RUN: ld.lld -T spill.ld nodwarf.o -o out3 --spill-coldest-first --irpgo-profile=profile-nodwarf.prof --enable-non-contiguous-regions
# RUN: llvm-readelf -S out3 | FileCheck %s --check-prefix=CASE3

# CASE3:      .text       PROGBITS 0000000000000000 {{.*}} 000004
# CASE3-NEXT: .text_spill PROGBITS 0000000000001000 {{.*}} 000004

## Case 4: Diagnostic warning when --spill-coldest-first passed without --irpgo-profile
# RUN: ld.lld -T spill.ld asm.o -o out4 --spill-coldest-first --enable-non-contiguous-regions 2>&1 | FileCheck %s --check-prefix=WARN-EMPTY

# WARN-EMPTY: warning: spill-coldest-first enabled but irpgo-profile is empty

## Case 5: Diagnostic warning when profile file is missing
# RUN: ld.lld -T spill.ld asm.o -o out5 --spill-coldest-first --irpgo-profile=nonexistent.prof --enable-non-contiguous-regions 2>&1 | FileCheck %s --check-prefix=WARN-MISSING

# WARN-MISSING: warning: failed to read profile nonexistent.prof

## Case 6: Flag disabling (--no-spill-coldest-first)
# RUN: ld.lld -T spill.ld asm.o -o out6 --spill-coldest-first --no-spill-coldest-first --irpgo-profile=profile.prof --enable-non-contiguous-regions
# RUN: llvm-readelf -S out6 | FileCheck %s --check-prefix=CASE2

#--- spill.ld
MEMORY {
  RAM (rwx) : ORIGIN = 0x0, LENGTH = 4
  FLASH (rwx) : ORIGIN = 0x1000, LENGTH = 0x1000
}

SECTIONS {
  .text : {
    *(.text.hot_func)
    *(.text.cold_func)
    *(.text.nodwarf_hot)
    *(.text.nodwarf_cold)
  } > RAM

  .text_spill : {
    *(.text.hot_func)
    *(.text.cold_func)
    *(.text.nodwarf_hot)
    *(.text.nodwarf_cold)
  } > FLASH
}

#--- asm.s
.file 1 "test.c"
.text
.section .text.hot_func,"ax",@progbits
.globl hot_func
.type hot_func, @function
hot_func:
.loc 1 1 0
  nop
  nop
  nop
  nop
.size hot_func, .-hot_func

.section .text.cold_func,"ax",@progbits
.globl cold_func
.type cold_func, @function
cold_func:
.loc 1 10 0
  nop
  nop
  nop
  nop
.size cold_func, .-cold_func

#--- nodwarf.s
.text
.section .text.nodwarf_hot,"ax",@progbits
.globl nodwarf_hot
.type nodwarf_hot, @function
nodwarf_hot:
  nop
  nop
  nop
  nop
.size nodwarf_hot, .-nodwarf_hot

.section .text.nodwarf_cold,"ax",@progbits
.globl nodwarf_cold
.type nodwarf_cold, @function
nodwarf_cold:
  nop
  nop
  nop
  nop
.size nodwarf_cold, .-nodwarf_cold

#--- profile.prof
hot_func:1000:100
 1: 1000
cold_func:10:1
 10: 10

#--- profile-nodwarf.prof
nodwarf_hot:1000:100
 1: 1000
nodwarf_cold:10:1
 10: 10

#--- empty.prof
