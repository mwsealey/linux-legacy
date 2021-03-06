/*
 * Freescale STMP378X low level RAM frequency manipulation
 *
 * Author: Vitaly Wool <vital@embeddedalley.com>
 *
 * Copyright 2008 Freescale Semiconductor, Inc. All Rights Reserved.
 * Copyright 2008 Embedded Alley Solutions, Inc All Rights Reserved.
 */

/*
 * The code contained herein is licensed under the GNU General Public
 * License. You may obtain a copy of the GNU General Public License
 * Version 2 or later at the following locations:
 *
 * http://www.opensource.org/licenses/gpl-license.html
 * http://www.gnu.org/copyleft/gpl.html
 */
#include <linux/linkage.h>
#include <asm/assembler.h>
#include <mach/hardware.h>
#include <asm/system.h>
#include <asm/pgtable-hwdef.h>
#include <mach/platform.h>
#include <mach/regs-power.h>
#include <mach/regs-clkctrl.h>
#include <mach/regs-emi.h>
#include <mach/regs-dram.h>

/* TODO should be move to clock.h */
#define SCALING_DATA_EMI_DIV_OFFSET     0
#define SCALING_DATA_FRAC_DIV_OFFSET    4
#define SCALING_DATA_CUR_FREQ_OFFSET    8
#define SCALING_DATA_NEW_FREQ_OFFSET    12

.global cpu_arm926_switch_mm

.align 8
ENTRY(stmp3xxx_ram_freq_scale)
	stmfd	sp!, {r1 - r9, lr}

	ldr	r5, [r0, #SCALING_DATA_NEW_FREQ_OFFSET]
	ldr	r6, [r0, #SCALING_DATA_CUR_FREQ_OFFSET]
	ldr	r7, [r0, #SCALING_DATA_EMI_DIV_OFFSET]
	ldr	r8, [r0, #SCALING_DATA_FRAC_DIV_OFFSET]

	adr	r9, __stmp_temp_stack

	@ clean cache
	ldr	r1, __stmp_flush_cache_addr
	mov	lr, pc
	mov	pc, r1

	@ put DRAM into self refresh
	ldr	r0, __stmp_dram_ctl00
	ldr	r1, [r0, #0x20]
	orr	r1, r1, #(1 << 8)
	str	r1, [r0, #0x20]
	@ wait for it to actually happen
	ldr	r0, __stmp_dram_emi00
1:	ldr	r1, [r0, #0x10]
	tst	r1, #(1 << 1)
	beq	1b
	nop

	@ prepare for change
	cmp	r5, #24
	bgt	2f
	bl	stmp3xxx_ram_24M_set_timings
	b	100f
2:	cmp	r5, #48
	bgt	3f
	bl	stmp3xxx_ram_48M_set_timings
	b	100f
3:	cmp	r5, #60
	bgt	4f
	bl	stmp3xxx_ram_60M_set_timings
	b	100f
4:	cmp	r5, #80
	bgt	5f
	bl	stmp3xxx_ram_80M_set_timings
	b	100f
5:	cmp	r5, #96
	bgt	6f
	bl	stmp3xxx_ram_96M_set_timings
	b	100f
6:	cmp	r5, #120
	bgt	7f
	bl	stmp3xxx_ram_120M_set_timings
	b	100f
7:	cmp     r5, #133
	bgt	8f
	bl	stmp3xxx_ram_133M_set_timings
	b	100f
8:	bl	stmp3xxx_ram_150M_set_timings

100:
	@ RAM to clk from xtal
	mov	r0, #(HW_CLKCTRL_CLKSEQ_ADDR & 0x000000FF)
	orr	r0, r0, #(HW_CLKCTRL_CLKSEQ_ADDR & 0x0000FF00)
	orr	r0, r0, #(HW_CLKCTRL_CLKSEQ_ADDR & 0x00FF0000)
	orr	r0, r0, #(HW_CLKCTRL_CLKSEQ_ADDR & 0xFF000000)
	mov	r1, #(1<<6)
	str	r1, [r0, #4]
	mov	r0, #(HW_CLKCTRL_EMI_ADDR & 0x000000FF)
	orr	r0, r0, #(HW_CLKCTRL_EMI_ADDR & 0x0000FF00)
	orr	r0, r0, #(HW_CLKCTRL_EMI_ADDR & 0x00FF0000)
	orr	r0, r0, #(HW_CLKCTRL_EMI_ADDR & 0xFF000000)
101:	ldr     r1, [r0]
	tst     r1, #BM_CLKCTRL_EMI_BUSY_REF_XTAL
	bne     101b

	@When are using the DLL, reset the DRAM controller and DLL
	@start point logic (via DLL_SHIFT_RESET and DLL_RESET).
	@After changing clock dividers and loading
	@the new HW_DRAM_CTL* parameters, we will wait for a new DLL_LOCK

	@todo - for DRAM's that will use DLL bypass (non DDR1)
	@	we should not use DLL_RESET and DLL_SHIFT_RESET.

	mov     r0,     #(HW_EMI_CTRL_ADDR & 0x000000FF)
	orr     r0, r0, #(HW_EMI_CTRL_ADDR & 0x0000FF00)
	orr     r0, r0, #(HW_EMI_CTRL_ADDR & 0x00FF0000)
	orr     r0, r0, #(HW_EMI_CTRL_ADDR & 0xFF000000)
	ldr     r1, [r0]            @read values of HW_EMI_CTRL into R1
	orr r1, r1, #BM_EMI_CTRL_DLL_SHIFT_RESET    @Set these 2 fields.
	orr r1, r1, #BM_EMI_CTRL_DLL_RESET
	str     r1, [r0]            @write back values to HW_EMI_CTRL register.

	bl	__stmp_emi_set_values

	@ EMI back to PLL
	mov	r0, #(HW_CLKCTRL_CLKSEQ_ADDR & 0x000000FF)
	orr	r0, r0, #(HW_CLKCTRL_CLKSEQ_ADDR & 0x0000FF00)
	orr	r0, r0, #(HW_CLKCTRL_CLKSEQ_ADDR & 0x00FF0000)
	orr	r0, r0, #(HW_CLKCTRL_CLKSEQ_ADDR & 0xFF000000)
	mov	r1, #(1<<6)
	str	r1, [r0, #8]

	@ Wait for BUSY_REF_EMI, to assure new clock dividers
	@ are done transferring
	mov	r0, #(HW_CLKCTRL_EMI_ADDR & 0x000000FF)
	orr	r0, r0, #(HW_CLKCTRL_EMI_ADDR & 0x0000FF00)
	orr	r0, r0, #(HW_CLKCTRL_EMI_ADDR & 0x00FF0000)
	orr	r0, r0, #(HW_CLKCTRL_EMI_ADDR & 0xFF000000)
1:	ldr	r1, [r0]
	tst	r1, #BM_CLKCTRL_EMI_BUSY_REF_EMI
	bne	1b
	str	r1, [r0]

@todo - for DRAM's that will use DLL bypass (non DDR1)
@we should not use DLL_RESET and DLL_SHIFT_RESET.
@	if(HW_DRAM_CTL04.B.DLL_BYPASS_MODE==0)
@	{
@
@	    Clear the DLL_RESET and DLL_SHIFT_RESET bitfields
@	    (\todo - is that necessary?
@	     they were already set previously to reset
@            the controller/DLL start point,
@	     so clearing should have no effect..)
@
@	     BF_CS2(EMI_CTRL, DLL_RESET, 0, DLL_SHIFT_RESET, 0);

	mov     r0,     #(HW_EMI_CTRL_ADDR & 0x000000FF)
	orr     r0, r0, #(HW_EMI_CTRL_ADDR & 0x0000FF00)
	orr     r0, r0, #(HW_EMI_CTRL_ADDR & 0x00FF0000)
	orr     r0, r0, #(HW_EMI_CTRL_ADDR & 0xFF000000)
	ldr     r1, [r0]
	bic r1, #BM_EMI_CTRL_DLL_SHIFT_RESET
	bic r1, #BM_EMI_CTRL_DLL_RESET
	str     r1, [r0]

@Wait for BUSY_REF_EMI, to assure new clock dividers are done transferring.
@(\todo is that necessary.  we already did this above.
	mov     r0,     #(HW_CLKCTRL_EMI_ADDR & 0x000000FF)
	orr     r0, r0, #(HW_CLKCTRL_EMI_ADDR & 0x0000FF00)
	orr     r0, r0, #(HW_CLKCTRL_EMI_ADDR & 0x00FF0000)
	orr     r0, r0, #(HW_CLKCTRL_EMI_ADDR & 0xFF000000)
66:	ldr     r1, [r0]
	tst     r1, #BM_CLKCTRL_EMI_BUSY_REF_EMI
	bne     66b

@ Wait for DLL locking.
@        while(HW_DRAM_CTL04.B.DLLLOCKREG==0);

	mov     r0,     #(HW_DRAM_CTL04_ADDR & 0x000000FF)
	orr     r0, r0, #(HW_DRAM_CTL04_ADDR & 0x0000FF00)
	orr     r0, r0, #(HW_DRAM_CTL04_ADDR & 0x00FF0000)
	orr     r0, r0, #(HW_DRAM_CTL04_ADDR & 0xFF000000)
77:	ldr     r1, [r0]
	tst     r1, #BM_DRAM_CTL04_DLLLOCKREG
	beq     77b


	@ resttore normal DRAM mode
        ldr     r0, __stmp_dram_ctl00
        ldr     r1, [r0, #0x20]
        bic     r1, r1, #(1 << 8)
        str     r1, [r0, #0x20]

        @ wait for it to actually happen
        ldr     r0, __stmp_dram_emi00
102:    ldr     r1, [r0, #0x10]
        tst     r1, #(1 << 1)
        bne     102b

@ restore regs and return
	ldmfd   sp!, {r1 - r9, lr}
	mov	pc, lr

	.space	0x100
__stmp_temp_stack:
	.word	0

#include "emi.inc"

__stmp_flush_cache_addr:
	.word	arm926_flush_kern_cache_all

ENTRY(stmp3xxx_ram_funcs_sz)
	.word	. - stmp3xxx_ram_freq_scale

