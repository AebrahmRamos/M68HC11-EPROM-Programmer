; ======================================================================
; HC11 EPROM PROGRAMMER (Part 2) - FIXED BRANCH RANGE
; Target: 2764 (NMOS) | Algo: 1ms Pulse + Verify + Overprogram
; ======================================================================

REGBAS  EQU     $1000
PORTA   EQU     $00
PORTB   EQU     $04
PORTC   EQU     $03
DDRC    EQU     $07
SCSR    EQU     $2E
SCDR    EQU     $2F
HPRIO   EQU     $3C
STACK   EQU     $00FF

; Constants
MAX_RETRIES EQU 25
VPROG_BIT   EQU %00100000   ; PA5? Wait, PA3 is PSU. 
; CORRECTION: Based on your previous code structure:
; PA3 = PSU (High Voltage Control)
; PA4 = PGM
; PA5 = OE
; PA6 = CE

        ORG     $0000           ; Must start at 0000 for Bootloader

START:
        LDS     #STACK
        LDX     #REGBAS         ; X points to Registers ($1000)

        ; 1. Force Single Chip Mode
        LDAA    #$C0
        STAA    HPRIO,X

        ; 2. Config Port A
        ; Default: PSU Off(0), Others Inactive(1) -> 0111 0000 ($70)
        LDAA    #$70
        STAA    PORTA,X

        ; 3. Config Serial (9600 Baud)
        LDAA    #$30
        STAA    $2B,X           ; BAUD
        LDAA    #$0C
        STAA    $2D,X           ; SCCR2

        ; 4. Wait for PC to switch baud rate
        JSR     DELAY_1S

MAIN_LOOP:
        JSR     RX_BYTE         ; Wait for command
        CMPA    #'B'
        BEQ     DO_BLANK
        CMPA    #'P'
        BEQ     DO_PROGRAM
        CMPA    #'R'
        BEQ     DO_READ
        BRA     MAIN_LOOP

; --- BLANK CHECK ---
DO_BLANK:
        JSR     PSU_READ        ; Vcc=5V
        CLRB                    ; B = Addr Count (0-24)
BL_LOOP:
        JSR     READ_BYTE_SUB   ; Read byte at Addr B into A
        CMPA    #$FF
        ;BNE     SEND_FAIL
        INCB
        CMPB    #25
        BNE     BL_LOOP
        ;BRA     SEND_OK

; --- READ ROUTINE ---
DO_READ:
        JSR     PSU_READ
        CLRB
RD_LOOP:
        JSR     READ_BYTE_SUB
        JSR     TX_BYTE         ; Send Data
        INCB
        CMPB    #25
        BNE     RD_LOOP
        JMP     MAIN_LOOP       ; Long jump back to main

; --- PROGRAM ROUTINE ---
DO_PROGRAM:
        ; 1. Enable High Voltage (Vpp=13V, Vcc=6V)
        JSR     PSU_PROG
        JSR     DELAY_50MS      ; Wait for rise

        CLRB                    ; B = Addr Count
PROG_L:
        JSR     RX_BYTE         ; Receive Data Byte from PC
        PSHB                    ; Save Addr
        
        ; Programming Algorithm
        STAB    PORTB,X         ; Set Address
        STAA    PORTC,X         ; Set Data
        
        PSHA                    ; Save Data
        LDAA    #$FF
        STAA    DDRC,X          ; Port C Output
        
        ; CE Low (Enable Chip)
        BCLR    PORTA,X $40     
        
        CLR     $50             ; Pulse Counter N = 0 (using address $0050)
        
PULSE_L:
        ; 1ms Program Pulse (PGM Low)
        BCLR    PORTA,X $10     ; PA4 Low
        JSR     DELAY_1MS
        BSET    PORTA,X $10     ; PA4 High
        
        INC     $50             ; N++
        
        ; Verify Step
        CLR     DDRC,X          ; Float Bus
        BCLR    PORTA,X $20     ; OE Low (PA5)
        NOP                     ; Access delay
        LDAA    PORTC,X         ; Read
        BSET    PORTA,X $20     ; OE High
        
        PULB                    ; Restore Target Data (into B temporarily)
        PSHB                    ; Push back for next iter
        CBA                     ; Compare Read(A) vs Target(B)
        BEQ     OVER_PROG       ; Match? Go to Overprogram
        
        ; Restore Bus for next pulse
        LDAA    #$FF
        STAA    DDRC,X
        STAB    PORTC,X         ; Put data back
        
        LDAA    $50
        CMPA    #25             ; MAX_RETRIES
        
        ; FIX 1: LONG BRANCH LOGIC
        BEQ     PROG_FAIL_JMP   ; If Equal to 25, Fail.
        JMP     PULSE_L         ; Else, Long Jump back
        
PROG_FAIL_JMP:
        ; Fail
        PULA                    ; Clean stack
        PULB                    ; Clean Addr
        JSR     PSU_READ        ; Safety Shutdown
        JMP     SEND_FAIL       ; Long jump

OVER_PROG:
        ; Overprogram Pulse = 3ms * N
        PULA                    ; Clean Stack (Target Data)
        
        LDAA    #$FF
        STAA    DDRC,X          ; Drive Data again
        PULB                    ; Get Target Data
        STAB    PORTC,X         ; Assert Data
        
        ; PGM Low
        BCLR    PORTA,X $10
        
        LDAA    $50             ; Get N
OV_L:   
        JSR     DELAY_1MS
        JSR     DELAY_1MS
        JSR     DELAY_1MS
        DECA
        
        ; FIX 2: LONG BRANCH LOGIC
        BEQ     OV_DONE         ; If A=0, done
        JMP     OV_L            ; Else, Long jump back
OV_DONE:
        
        ; PGM High
        BSET    PORTA,X $10
        
        ; CE High (Disable)
        BSET    PORTA,X $40
        CLR     DDRC,X          ; Float Bus
        
        INCB                    ; Next Address (B was restored by PULB)
        CMPB    #25
        BEQ     PROG_DONE       ; If 25, done
        JMP     PROG_L          ; Else, next byte
        
PROG_DONE:
        JSR     PSU_READ
        JMP     SEND_OK

; --- SUBROUTINES ---

READ_BYTE_SUB:
        STAB    PORTB,X         ; Address
        CLR     DDRC,X          ; Input
        BCLR    PORTA,X $60     ; CE/OE Low
        NOP
        LDAA    PORTC,X         ; Read
        BSET    PORTA,X $60     ; CE/OE High
        RTS

SEND_OK:
        LDAA    #'K'
        BRA     TX_JMP
SEND_FAIL:
        LDAA    #'F'
TX_JMP: JSR     TX_BYTE
        JMP     MAIN_LOOP

PSU_PROG:
        BSET    PORTA,X $08     ; PA3 High
        RTS
PSU_READ:
        BCLR    PORTA,X $08     ; PA3 Low
        RTS

RX_BYTE:
        BRCLR   SCSR,X $20 RX_BYTE
        LDAA    SCDR,X
        RTS
TX_BYTE:
        BRCLR   SCSR,X $80 TX_BYTE
        STAA    SCDR,X
        RTS

DELAY_1S:
        PSHY
        LDY     #1000
        BRA     DL_LOOP
DELAY_50MS:
        PSHY
        LDY     #50
DL_LOOP:
        JSR     DELAY_1MS
        DEY
        BNE     DL_LOOP
        PULY
        RTS

DELAY_1MS:
        PSHX
        LDX     #266
D1:     DEX
        BNE     D1
        PULX
        RTS