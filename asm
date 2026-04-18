#define	temp0		r21
#define	temp1		r20
#define	temp2		r19
#define	temp3		r18

#define	XL		r26
#define	XH		r27

#define nop2		rjmp	.+0	/* jump to next instruction */

#if F_CPU == 16000000UL
 #define TRGWAIT	lo8((48*(16000000/1000000))/3)
#endif

;-------------------------------------------------------------------------------
;*******************************************************************************
;-------------------------------------------------------------------------------

; Note: the following variables MUST be in the same 256 byte RAM segment !!

	.section	.bss,"aw",@nobits

	.global sw_idbuf
	.global sw_packet3
	.global sw_packet2
	.global sw_packet1
	.global ffp_packet

	.global sw_pktptr
	.global sw_clkcnt

	.skip 1,0

sw_idbuf:
        .skip 60,0

sw_packet3:				; SideWinder 3D Pro packet buffers
        .skip 8,0

sw_packet2:
        .skip 8,0

sw_packet1:
        .skip 2,0

ffp_packet:
        .skip 6,0
sw_pktstart:

sw_pktptr:				; LSB of -> to current byte in buffer
	.skip 1,0

sw_clkcnt:				; no. of clock ticks on B1
	.skip 1,0

;-------------------------------------------------------------------------------
;*******************************************************************************
;-------------------------------------------------------------------------------

	.text

;-------------------------------------------------------------------------------
;*******************************************************************************
;	Receive, decode, and store a triplet from the 3DPro, PP, or FFP
;-------------------------------------------------------------------------------

	.global INT0_vect

INT0_vect:
	push	temp0			; Save temp0				2		+2
	in      temp0,SREG		; Save S register			1
	push	temp0			; Save SREG				2

	ldi	temp0,T6TO100US		; 					1
	out	TCNT0,temp0		; Reset timeout timer			1

	push	temp1			; Save temp1				2
	push	XL			; Save XL				2
	push	XH			; Save XH				2		+4

	ldi	XH,hi8(sw_pktstart)	; Load buffer pointer H	!!!		1		+5
	lds	XL,sw_pktptr		; Load buffer pointer L			2	+4

	lds	temp0,sw_clkcnt		; Load clkcnt				2		+6
	mov	temp1,temp0		;					1		+7

	inc	temp0			; Maintain clkcnt			1
	sts	sw_clkcnt,temp0		; Save new clkcnt			2		+9

	in	temp0,BUTPIN		; Read the button data			1
	swap	temp0			; AT90USBX2				1
	andi	temp0,0b11100000	; Mask B4-B2				1

	andi	temp1,7			;					1	12+	01234567
	breq	I0case0			;					1/2		21111111
	cpi	temp1,5			;					1		 1111111
	breq	I0case5			;					1/2		 1111211
	cpi	temp1,2			;					1		 1111 11
	breq	I0case2			;					1/2		 1211 11
	cpi	temp1,3			;					1		 1 11 11
	breq	I0case3			;					1/2		 1 21 11
	cpi	temp1,6			;					1		 1  1 11
	breq	I0case6			;					1/2		 1  1 21
	cpi	temp1,1			;					1		 1  1  1
	breq	I0case1			;					1/2		 2  1  1
	cpi	temp1,4			;					1		    1  1
	breq	I0case4			;					1/2		    2  1
	rjmp	I0case7			;					2		       2
					;							 1  1 11
					;							22684405
I0case0:
	swap	temp0			; move b7-b5 (B4-B3) to b2-b0		1
	lsr	temp0			;					1 -2

	st	-X,temp0		; Store it				2

	rjmp	Int0End			;					2		8+2=10 +21=31

I0case2:
	lsl	temp0			; store b7 in C, b6-b5 to b7-b6		1

	ld	temp1,X			; Get current byte			2
	or	temp0,temp1		;					1
	st	X,temp0			; Save to buffer			2

	clr	temp0			;					1
	rol	temp0			; b7 to b0				1
	st	-X,temp0		; Save to buffer			2

	rjmp	Int0End			;					2		  12+6=18 +21=39

I0case5:
	bst	temp0,7			; store b7 in T				1
	lsl	temp0			; drop b7				1
	lsl	temp0			; store b6 in C, b5 to b7		1

	ld	temp1,X			; Get current byte			2
	or	temp0,temp1		;					1
	st	X,temp0			; Save to buffer			2

	clr	temp0			;					1
	rol	temp0			; b6 to b0				1
	bld	temp0,1			; b7 to b1				1
	st	-X,temp0		; Save to buffer			2

	rjmp	Int0End			;					2		     15+4=19 +21=40

I0case3:				; b7-b5 to b3-b1					   9+8=17 +21=38
	lsr	temp0			;					1
I0case6:				; b7-b5 to b4-b2					      8+10=18 +21=39
	lsr	temp0			;					1
I0case1:				; b7-b5 to b5-b3					 7+12=19 +21=40
	lsr	temp0			;					1
I0case4:				; b7-b5 to b6-b4					    6+14=20 +21=41
	lsr	temp0			;					1
I0case7:				; b7-b5 are right					       5+15=20 +21=41
	ld	temp1,X			; Get current byte			2
	or	temp0,temp1		;					1
	st	X,temp0			; Save to buffer			2

Int0End:
	sts	sw_pktptr,XL		; Save buffer pointer L			2

	pop	XH			; Restore XH				2		+11
	pop	XL			; Restore XL				2	+4
	pop	temp1			; Restore temp1				2

	pop	temp0			; Restore SREG				2
	out	SREG,temp0		; Restore S register			1

	pop	temp0			; Restore temp0				2		+13
	reti				;					4	9+

;-------------------------------------------------------------------------------
;*******************************************************************************
;	Decode the raw FFP/PP data and store it into sw_report
;
; Input:
;	Pointer to start of packet to copy
;
;	FFP/PP data packet structure
;	============================
;
;	44444444 33333333 33222222 22221111 11111100 00000000
;	76543210 98765432 10987654 32109876 54321098 76543210
;	-------0 -------1 -------2 -------3 -------4 -------5
;	ppHHHHRR RRRRTTTT TTTYYYYY YYYYYXXX XXXXXXXB BBBBBBBB
;	  321054 32106543 21098765 43210987 65432109 87654321
;
;	USB report data structure
;	=========================
;
;	-------0 -------1 -------2 -------3 -------4 -------5
;	XXXXXXXX YYYYYYXX HHHHYYYY BBRRRRRR TBBBBBBB 00TTTTTT
;	76543210 54321098 32109876 21543210 09876543   654321
;
;-------------------------------------------------------------------------------

#define	argPtrL		r24
#define	argPtrH		r25

	.global CopyFFPData

CopyFFPData:
	movw	XL,argPtrL

	; X

	ldi	temp0,4
	add	XL,temp0

	ld	temp0,X			; xl:6543210-

	com	temp0
	bst	temp0,0			;  b:9
	com	temp0

	subi	XL,1
	ld	temp2,X			; xh:-----987

	lsr	temp2			; xh:------98 [7]
	ror	temp0			; xl:76543210

	sts	sw_report,temp0

	ldi	temp1,0b00000010
	add	temp2,temp1		; Add -512
	andi	temp2,0b00000011	; xh:------98

	; Y

	ld	temp0,X			; yl:43210---

	subi	XL,1
	ld	temp1,X			; yh:---98765

	lsr	temp1			; yh:----9876 [5]
	ror	temp0			; yl:543210--

	andi	temp0,0b11111100

	or	temp0,temp2

	sts	sw_report+1,temp0

	ldi	temp2,0b00001000
	add	temp1,temp2		; Add -512
	andi	temp1,0b00001111	; yh:----9876

	; Hat

	subi	XL,2
	ld	temp0,X			;  h:--3210--

	lsl	temp0			;  h:-3210---
	lsl	temp0			;  h:3210----
	subi	temp0,0x10		; -1
	andi	temp0,0b11110000

	or	temp0,temp1

	sts	sw_report+2,temp0

	; Rz

	ld	temp2,X			; rh:------54

	ldi	temp1,0b00000010
	add	temp2,temp1		; Add -32
	andi	temp2,0b00000011

	inc	XL

	ld	temp1,X			; rl:3210----
	andi	temp1,0b11110000

	or	temp2,temp1		;  r:3210--54
	swap	temp2			;  r:--543210
	lsl	temp2			;  r:-543210-
	lsl	temp2			;  r:543210--

	; B1-9

	ldi	temp0,4
	add	XL,temp0
	ld	temp0,X			;  b:87654321

	com	temp0

	lsr	temp0			;  b:-8765432 [1]
	ror	temp2			;  r:1543210-
	lsr	temp0			;  b:--876543 [2]
	ror	temp2			;  r:21543210

	sts	sw_report+3,temp2

	bld	temp0,6			;  b:-9876543

	; Throttle

	subi	XL,3
	ld	temp1,X			; tl:210-----

	bst	temp1,5
	bld	temp0,7			;  b:09876543

	sts	sw_report+4,temp0

	subi	XL,1
	ld	temp0,X			; th:----6543

	ldi	temp2,0b00001000
	add	temp0,temp2		; Add -64
	andi	temp0,0b00001111

	lsl	temp1			; tl:1------- [2]
	rol	temp0			; th:---65432
	lsl	temp1			; tl:-------- [1]
	rol	temp0			; th:--654321

	sts	sw_report+5,temp0

	ret

;-------------------------------------------------------------------------------
;*******************************************************************************
;	Decode the raw 3DPro data and store it into sw_report
;
; Input:
;	Pointer to start of packet to copy
;
;	3D Pro data packet structure
;	============================
;
;	0   **** 0        0        0        0        0        0        1
;	66665555 55555544 44444444 33333333 33222222 22221111 11111100 00000000
;	32109876 54321098 76543210 98765432 10987654 32109876 54321098 76543210
;	-------0 -------1 -------2 -------3 -------4 -------5 -------6 -------7
;	sHHHcccc sTTTTTTT sRRRRRRR sBBRRTTT sYYYYYYY sXXXXXXX sBBBBBBB sHXXXYYY
;	 210      6543210  6543210  8987987  6543210  6543210  7654321  3987987
;
;	USB report data structure
;	=========================
;
;	-------0 -------1 -------2 -------3 -------4 -------5 -------6
;	XXXXXXXX YYYYYYXX RRRRYYYY HHHRRRRR BBBBBBBH TTTTTTTB 00000TTT
;	76543210 54321098 32109876 21087654 76543213 65432108      987
;
;-------------------------------------------------------------------------------

	.global Copy3DPData

Copy3DPData:
	movw	XL,argPtrL

	; Get X

	ldi	temp1,5
	add	XL,temp1

	ld	temp0,X			; xl:-6543210

	inc	XL
	inc	XL

	ld	temp2,X
	andi	temp2,0b00111000	; xh:--987---

	lsl	temp2			; xh:-987----
	swap	temp2			; xh:-----987
	lsl	temp0			; xl:6543210-
	lsr	temp2			; xh:------98 [7]
	ror	temp0			; xl:76543210

	ldi	temp1,0xFE
	add	temp2,temp1		; Add -512
	andi	temp2,0b00000011	; xh:------98

	sts	sw_report,temp0

	; Y

	ld	temp1,X
	andi	temp1,0b00000111	; yh:-----987

	subi	XL,3

	ld	temp0,X			; yl:-6543210

	lsl	temp0			; yl:6543210-
	lsr	temp1			; yh:------98 [7]
	ror	temp0			; yl:76543210

	ldi	temp3,0xFE
	add	temp1,temp3		; Add -512
	andi	temp1,0b00000011	; yh:------98

	lsl	temp0			; yl:6543210-
	rol	temp1			; yh:-----987
	lsl	temp0			; yl:543210--
	rol	temp1			; yh:----8976
	or	temp0,temp2

	sts	sw_report+1,temp0
	mov	temp2,temp1

	; Rz

	subi	XL,2

	ld	temp0,X			; rl:-6543210

	inc	XL

	ld	temp1,X
	andi	temp1,0b00011000	; rh:---87---

	lsl	temp0			; rl:6543210-
	lsl	temp1			; rh:--87----
	swap	temp1			; rh:------87
	lsr	temp1			; rh:-------8 [7]
	ror	temp0			; rl:76543210

	com	temp1			; Add -256
	bst	temp1,0

	swap	temp0			; rl:32107654
	mov	temp1,temp0
	andi	temp1,0b11110000	; rl:3210----
	or	temp1,temp2

	sts	sw_report+2,temp1
	andi	temp0,0b00001111	; rh:----7654
	bld	temp0,4			; rh:---87654
	mov	temp2,temp0

	;  Hat

	subi	XL,3

	ld	temp0,X
	andi	temp0,0b01110000	; h:-210----

	ldi	temp1,7
	add	XL,temp1

	ld	temp1,X			; h:-3------

	bst	temp1,6
	bld	temp0,7			; h:3210----
	subi	temp0,0x10

	bst	temp0,7
	lsl	temp0			; h:210-----
	or	temp0,temp2

	sts	sw_report+3,temp0
	clr	temp2
	bld	temp2,0			; h:-------3

	;  Buttons 1-8

	dec	XL

	ld	temp0,X			; b:-7654321

	subi	XL,3

	ld	temp1,X			; b:-89-----
	bst	temp1,6
	bld	temp0,7			; b:87654321

	com	temp0

	clr	temp1
	lsl	temp0			; b:7654321-
	rol	temp1			; b:-------8
	or	temp0,temp2

	sts	sw_report+4,temp0
	mov	temp2,temp1

	; Slider

	subi	XL,2

	ld	temp0,X			; sl:-6543210

	inc	XL
	inc	XL

	ld	temp1,X
	andi	temp1,0b00000111	; sh:-----987

	lsl	temp0			; sl:6543210-
	lsr	temp1			; sh:------98 [7]
	ror	temp0			; sl:76543210

	ldi	temp3,0xFE
	add	temp1,temp3		; Add -512
	andi	temp1,0b00000011

	bst	temp0,7
	lsl	temp0			; sl:6543210-
	or	temp0,temp2

	sts	sw_report+5,temp0

	lsl	temp1			; sh:-----98-
	bld	temp1,0

	sts	sw_report+6,temp1

	ret

;-------------------------------------------------------------------------------
;*******************************************************************************
;	Initiate and monitor data transfer from a 3DP/FFP/PP.
;	INT0 is left enabled upon exit.
;
; Input:
;	temp1	0 for data packet, -n for ID kick
;	temp2	No. of triplets to wait for
; Return:
;	1 - received, 0 - timed out
;-------------------------------------------------------------------------------

#define	argSZ		r22
#define	argID		r24

#define	resOkL		r24

	.global QueryFFP

QueryFFP:
	mov	temp1,argID
	mov	temp2,argSZ

	clr	resOkL			; Default return 0

	cli				; Disable interrupts

	sbi	EIFR,INTF0		; Clear INT condition
	sbi	EIMSK,INT0		; Enable INT

	clr	temp3

	sbis	BUTPIN,BUT1		; Button 1 pressed ?
	ser	temp3			; Yes, have to swallow 1st INT..

	ldi	temp0,_B1(PSRSYNC)	; reset prescaler
	out	GTCCR,temp0

	ldi	temp0,T6TO400US
	out	TCNT0,temp0		; Set up initial timeout

	sbi	TIFR0,TOV0		; Clear overflow flag

	sts	sw_clkcnt,temp3		; Preset clock counter

	ldi	temp0,lo8(sw_pktstart)	; &ffp_packet[6]
	sts	sw_pktptr,temp0

	sei				;				1

Ptrigger:
	cbi	TRGDDR,TRGX1BIT		;				2
	cbi	TRGDDR,TRGY2BIT		;				2

	ldi	temp0,TRGWAIT		; wait 48us
1:	dec	temp0
	brne	1b

	sbi	TRGDDR,TRGX1BIT		;				2
	sbi	TRGDDR,TRGY2BIT		;				2

Ploop:
	lds	temp0,sw_clkcnt		;					+2
	cp	temp0,temp3		; Anything new ?		1
	brne	Pgotsome		;				1/2 = 2/3

	sbis	TIFR0,TOV0		; Timeout ? Skip if TOV set	1/2
	rjmp	Ploop			; Wait some more		2 = 4

	ret				; Signal timeout, return 0

Pgotsome:
	lds	temp0,sw_clkcnt		;				1	+1

	sub	temp0,temp3		; # clk's that occured		1
	add	temp3,temp0		; Correct clkcnt copy		1

	cp	temp3,temp2		; Got all we need ?		1
	brsh	Pdone			; Yes, done			1/2 = 6

	tst	temp1			; Kick pending ?		1
	brpl	Ploop			; Nope				1/2 = 8

	add	temp1,temp0		; Kick due ?			1
	brmi	Ploop			; Nope				1/2 = 10

	rjmp	Ptrigger		; Yes, kick			2 = 11

Pdone:					; Packet arrived..
	inc	resOkL			; Signal Ok, return 1
	ret

;-------------------------------------------------------------------------------
;*******************************************************************************
;	Initiate and monitor data transfer from a 3DPro.
;	INT0 is left enabled upon exit.
;
; Input:
;	temp1	0 for data packet, -n for ID kick
;	temp2	No. of triplets to wait for
; Return:
;	1 - received, 0 - timed out
;-------------------------------------------------------------------------------

	.global Query3DP

Query3DP:
	rcall	QueryFFP

	tst	resOkL
	breq	Qexit

	lds	temp0,sw_clkcnt
	cpi	temp0,DATSZ3DP		; If it's a data packet..
	brne	Qexit

	cli
	clr	temp0
	sts	sw_clkcnt,temp0		; Correct SWclkcnt and ptr so the next
	lds	temp0,sw_pktptr
	inc	temp0			; packet will allign w/ sw_packet2
	sts	sw_pktptr,temp0
	sei
Qexit:
	ret

;-------------------------------------------------------------------------------
; C equivalent (reference only)
;-------------------------------------------------------------------------------
;
; #include <stdbool.h>
; #include <stdint.h>
;
; struct SideWinderBuffers
; {
;     uint8_t pad;
;     uint8_t sw_idbuf[60];
;     uint8_t sw_packet3[8];
;     uint8_t sw_packet2[8];
;     uint8_t sw_packet1[2];
;     uint8_t ffp_packet[6];
; };
;
; static struct SideWinderBuffers sw_buffers;
;
; #define sw_idbuf     (sw_buffers.sw_idbuf)
; #define sw_packet3   (sw_buffers.sw_packet3)
; #define sw_packet2   (sw_buffers.sw_packet2)
; #define sw_packet1   (sw_buffers.sw_packet1)
; #define ffp_packet   (sw_buffers.ffp_packet)
;
; static uint8_t *const sw_pktstart = sw_buffers.ffp_packet + sizeof(sw_buffers.ffp_packet);
; static volatile uint8_t *sw_pktptr;
; static volatile uint8_t sw_clkcnt;
; extern uint8_t sw_report[7];
;
; static inline uint8_t swap8(uint8_t value)
; {
;     return (uint8_t)((value << 4) | (value >> 4));
; }
;
; static void INT0_vect_c(void)
; {
;     TCNT0 = T6TO100US;
;
;     uint8_t *ptr = (uint8_t *)sw_pktptr;
;     uint8_t phase = sw_clkcnt++;
;     uint8_t sample = (uint8_t)(swap8(BUTPIN) & 0xE0u);
;
;     switch (phase & 7u)
;     {
;         case 0:
;             *--ptr = (uint8_t)(sample >> 5);
;             break;
;
;         case 2:
;             *ptr |= (uint8_t)(sample << 1);
;             *--ptr = (uint8_t)(sample >> 7);
;             break;
;
;         case 5:
;             *ptr |= (uint8_t)(sample << 2);
;             *--ptr = (uint8_t)((sample >> 6) & 0x03u);
;             break;
;
;         case 3:
;             *ptr |= (uint8_t)(sample >> 4);
;             break;
;
;         case 6:
;             *ptr |= (uint8_t)(sample >> 3);
;             break;
;
;         case 1:
;             *ptr |= (uint8_t)(sample >> 2);
;             break;
;
;         case 4:
;             *ptr |= (uint8_t)(sample >> 1);
;             break;
;
;         default:
;             *ptr |= sample;
;             break;
;     }
;
;     sw_pktptr = ptr;
; }
;
; static void CopyFFPData_c(const uint8_t *packet)
; {
;     uint16_t x = (uint16_t)(((((uint16_t)packet[3]) & 0x07u) << 7) | ((packet[4] >> 1) & 0x7Fu));
;     uint16_t y = (uint16_t)(((((uint16_t)packet[2]) & 0x1Fu) << 5) | ((packet[3] >> 3) & 0x1Fu));
;     uint8_t hat = (uint8_t)((((packet[0] >> 2) & 0x0Fu) - 1u) & 0x0Fu);
;     uint8_t rz = (uint8_t)((((((uint8_t)packet[0]) & 0x03u) << 4) | ((packet[1] >> 4) & 0x0Fu)) - 32u);
;     uint8_t buttons = (uint8_t)~packet[5];
;     uint8_t button9 = (uint8_t)((((uint8_t)~packet[4]) & 0x01u) << 6);
;     uint8_t throttle = (uint8_t)((((((uint8_t)packet[1]) & 0x0Fu) << 3) | ((packet[2] >> 5) & 0x07u)) - 64u);
;
;     x = (uint16_t)((x - 512u) & 0x03FFu);
;     y = (uint16_t)((y - 512u) & 0x03FFu);
;
;     sw_report[0] = (uint8_t)x;
;     sw_report[1] = (uint8_t)(((y & 0x3Fu) << 2) | ((x >> 8) & 0x03u));
;     sw_report[2] = (uint8_t)((hat << 4) | ((y >> 6) & 0x0Fu));
;     sw_report[3] = (uint8_t)(((buttons & 0x03u) << 6) | (rz & 0x3Fu));
;     sw_report[4] = (uint8_t)(((throttle & 0x01u) << 7) | button9 | ((buttons >> 2) & 0x3Fu));
;     sw_report[5] = (uint8_t)((throttle >> 1) & 0x3Fu);
; }
;
; static void Copy3DPData_c(const uint8_t *packet)
; {
;     uint16_t x = (uint16_t)(((((uint16_t)packet[7] >> 3) & 0x07u) << 7) | (packet[5] & 0x7Fu));
;     uint16_t y = (uint16_t)(((((uint16_t)packet[7] >> 0) & 0x07u) << 7) | (packet[4] & 0x7Fu));
;     uint16_t rz = (uint16_t)(((((uint16_t)packet[3] >> 3) & 0x03u) << 7) | (packet[2] & 0x7Fu));
;     uint16_t slider = (uint16_t)(((((uint16_t)packet[3] >> 0) & 0x07u) << 7) | (packet[1] & 0x7Fu));
;     uint8_t hat = (uint8_t)((((((packet[7] >> 6) & 0x01u) << 3) | ((packet[0] >> 4) & 0x07u)) - 1u) & 0x0Fu);
;     uint8_t buttons = (uint8_t)~(((((packet[3] >> 6) & 0x01u) << 7) | (packet[6] & 0x7Fu)) & 0xFFu);
;
;     x = (uint16_t)((x - 512u) & 0x03FFu);
;     y = (uint16_t)((y - 512u) & 0x03FFu);
;     rz = (uint16_t)((rz - 256u) & 0x01FFu);
;     slider = (uint16_t)((slider - 512u) & 0x03FFu);
;
;     sw_report[0] = (uint8_t)x;
;     sw_report[1] = (uint8_t)(((y & 0x3Fu) << 2) | ((x >> 8) & 0x03u));
;     sw_report[2] = (uint8_t)(((rz & 0x0Fu) << 4) | ((y >> 6) & 0x0Fu));
;     sw_report[3] = (uint8_t)(((hat & 0x07u) << 5) | ((rz >> 4) & 0x1Fu));
;     sw_report[4] = (uint8_t)(((buttons & 0x7Fu) << 1) | ((hat >> 3) & 0x01u));
;     sw_report[5] = (uint8_t)(((slider & 0x7Fu) << 1) | ((buttons >> 7) & 0x01u));
;     sw_report[6] = (uint8_t)((slider >> 7) & 0x07u);
; }
;
; static inline void trigger_sidewinder_c(void)
; {
;     TRGDDR &= (uint8_t)~(_B1(TRGX1BIT) | _B1(TRGY2BIT));
;
;     for (uint8_t wait = TRGWAIT; wait != 0u; --wait)
;     {
;     }
;
;     TRGDDR |= (uint8_t)(_B1(TRGX1BIT) | _B1(TRGY2BIT));
; }
;
; static bool QueryFFP_c(int8_t kick_phase, uint8_t triplets_needed)
; {
;     uint8_t seen = 0u;
;
;     cli();
;     EIFR |= _B1(INTF0);
;     EIMSK |= _B1(INT0);
;
;     if ((BUTPIN & _B1(BUT1)) == 0u)
;     {
;         seen = 0xFFu;
;     }
;
;     GTCCR = _B1(PSRSYNC);
;     TCNT0 = T6TO400US;
;     TIFR0 |= _B1(TOV0);
;
;     sw_clkcnt = seen;
;     sw_pktptr = sw_pktstart;
;     sei();
;
;     trigger_sidewinder_c();
;
;     for (;;)
;     {
;         while (sw_clkcnt == seen)
;         {
;             if (TIFR0 & _B1(TOV0))
;             {
;                 return false;
;             }
;         }
;
;         uint8_t delta = (uint8_t)(sw_clkcnt - seen);
;         seen = (uint8_t)(seen + delta);
;         if (seen >= triplets_needed)
;         {
;             return true;
;         }
;
;         if (kick_phase < 0)
;         {
;             kick_phase = (int8_t)(kick_phase + (int8_t)delta);
;             if (kick_phase >= 0)
;             {
;                 trigger_sidewinder_c();
;             }
;         }
;     }
; }
;
; static bool Query3DP_c(int8_t kick_phase, uint8_t triplets_needed)
; {
;     if (!QueryFFP_c(kick_phase, triplets_needed))
;     {
;         return false;
;     }
;
;     if (sw_clkcnt == DATSZ3DP)
;     {
;         cli();
;         sw_clkcnt = 0;
;         ++sw_pktptr;
;         sei();
;     }
;
;     return true;
; }
;
;-------------------------------------------------------------------------------
;*******************************************************************************
;*  End of file
;*******************************************************************************
;-------------------------------------------------------------------------------