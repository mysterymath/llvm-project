# REQUIRES: x86
# RUN: rm -rf %t && split-file %s %t && cd %t
# RUN: llvm-mc -filetype=obj -triple=x86_64-pc-linux asm_data.s -o asm_data.o
# RUN: llvm-mc -filetype=obj -triple=x86_64-pc-linux nodwarf_data.s -o nodwarf_data.o

## Case 1: Data Section Spilling via DWARF DW_TAG_variable (cold_data spills to FLASH, hot_data stays in RAM)
# RUN: ld.lld -T spill_data.ld asm_data.o -o out1 --spill-coldest-first --irpgo-profile=profile_data.prof --enable-non-contiguous-regions
# RUN: llvm-readelf -S out1 | FileCheck %s --check-prefix=CASE1

# CASE1:      .data       PROGBITS 0000000000000000 {{.*}} 000004
# CASE1-NEXT: .data_spill PROGBITS 0000000000001000 {{.*}} 000004

## Case 2: Data Section Spilling via Symbol Table Fallback (No DWARF)
# RUN: ld.lld -T spill_data.ld nodwarf_data.o -o out2 --spill-coldest-first --irpgo-profile=profile_nodwarf_data.prof --enable-non-contiguous-regions
# RUN: llvm-readelf -S out2 | FileCheck %s --check-prefix=CASE2

# CASE2:      .data       PROGBITS 0000000000000000 {{.*}} 000004
# CASE2-NEXT: .data_spill PROGBITS 0000000000001000 {{.*}} 000004

## Case 3: Stable Tie-Breaking for Data Sections (Equal sample counts)
# RUN: ld.lld -T spill_data.ld asm_data.o -o out3 --spill-coldest-first --irpgo-profile=empty.prof --enable-non-contiguous-regions
# RUN: llvm-readelf -S out3 | FileCheck %s --check-prefix=CASE2

#--- spill_data.ld
MEMORY {
  RAM (rwx) : ORIGIN = 0x0, LENGTH = 4
  FLASH (rwx) : ORIGIN = 0x1000, LENGTH = 0x1000
}

SECTIONS {
  .data : {
    *(.data.hot_data)
    *(.data.cold_data)
    *(.data.nodwarf_hot_data)
    *(.data.nodwarf_cold_data)
  } > RAM

  .data_spill : {
    *(.data.hot_data)
    *(.data.cold_data)
    *(.data.nodwarf_hot_data)
    *(.data.nodwarf_cold_data)
  } > FLASH
}

#--- asm_data.s
.file 1 "test.c"
.data
.section .data.hot_data,"wa",@progbits
.globl hot_data
.type hot_data, @object
hot_data:
  .long 42
.size hot_data, 4

.section .data.cold_data,"wa",@progbits
.globl cold_data
.type cold_data, @object
cold_data:
  .long 24
.size cold_data, 4

.section .debug_abbrev,"",@progbits
  .byte 1      # Abbreviation code
  .byte 17     # DW_TAG_compile_unit
  .byte 1      # DW_CHILDREN_yes
  .byte 37     # DW_AT_producer
  .byte 8      # DW_FORM_string
  .byte 19     # DW_AT_language
  .byte 11     # DW_FORM_data2
  .byte 0, 0   # EOM

  .byte 2      # Abbreviation code
  .byte 52     # DW_TAG_variable
  .byte 0      # DW_CHILDREN_no
  .byte 3      # DW_AT_name
  .byte 8      # DW_FORM_string
  .byte 110    # DW_AT_linkage_name
  .byte 8      # DW_FORM_string
  .byte 2      # DW_AT_location
  .byte 24     # DW_FORM_exprloc
  .byte 0, 0   # EOM
  .byte 0      # EOM

.section .debug_info,"",@progbits
.long .Lcu_end - .Lcu_start # Length
.Lcu_start:
  .short 4     # DWARF Version
  .long .debug_abbrev # Abbrev offset
  .byte 8      # Address size
  .byte 1      # Abbrev code 1 (compile_unit)
  .asciz "clang"
  .short 12    # C99

  .byte 2      # Abbrev code 2 (variable hot_data)
  .asciz "hot_data"
  .asciz "hot_data"
  .byte 9      # Location expr length
  .byte 3      # DW_OP_addr
  .quad hot_data

  .byte 2      # Abbrev code 2 (variable cold_data)
  .asciz "cold_data"
  .asciz "cold_data"
  .byte 9      # Location expr length
  .byte 3      # DW_OP_addr
  .quad cold_data

  .byte 0      # End of children
.Lcu_end:

#--- nodwarf_data.s
.data
.section .data.nodwarf_hot_data,"wa",@progbits
.globl nodwarf_hot_data
.type nodwarf_hot_data, @object
nodwarf_hot_data:
  .long 100
.size nodwarf_hot_data, 4

.section .data.nodwarf_cold_data,"wa",@progbits
.globl nodwarf_cold_data
.type nodwarf_cold_data, @object
nodwarf_cold_data:
  .long 200
.size nodwarf_cold_data, 4

#--- profile_data.prof
hot_data:1000:100
 1: 1000
cold_data:10:1
 10: 10

#--- profile_nodwarf_data.prof
nodwarf_hot_data:1000:100
 1: 1000
nodwarf_cold_data:10:1
 10: 10

#--- empty.prof
