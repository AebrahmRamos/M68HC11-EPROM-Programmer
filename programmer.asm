; --- DEFINITIONS (Offsets from Base $1000) ---
REGBAS  EQU     $1000       ; Register Base Address

PORTA   EQU     $00         ; Offset for Port A
PORTB   EQU     $04         ; Offset for Port B
PORTC   EQU     $03         ; Offset for Port C
DDRC    EQU     $07         ; Offset for Data Direction C

BAUD    EQU     $2B         ; SCI Baud Register
SCCR2   EQU     $2D         ; SCI Control Register 2
SCSR    EQU     $2E         ; SCI Status Register
SCDR    EQU     $2F         ; SCI Data Register

HPRIO   EQU     $3C         ; Offset for HPRIO (Mode Select)

STACK   EQU     $00FF       ; Top of Internal RAM

; programming constants
MAX_RETRIES EQU 25          ; max number of retries for programming pulse
PGM_BIT   EQU   %00001000   ; bit 3 for program control (PA3)
VPROG_BIT EQU   %00010000   ; bit 4 for VPP control (PA4)
CE_BIT    EQU   %00100000   ; bit 5 for chip enable (PA5)
OE_BIT    EQU   %01000000   ; bit 6 for output enable (PA6)
DATA_BYTE EQU   $AA         ; test pattern to write (10101010)

; variable storage in RAM (page 0)
PULSE_COUNT EQU $0000       ; counter for programming pulses

        ORG     $0100       ; start of program in RAM (after page 0)

START:
        LDS     #STACK

        LDX     #REGBAS

        ; force single chip mode (MDA=0) but keep boot ROM enabled (rboot=1)
        LDAA    #$C0        
        STAA    HPRIO,X     ; write to $103C

        ; make sure Port C is set as input (it should default to this anyway)
        LDAA    #$00        ; set Port C as input
        STAA    DDRC,X      ; write to $1007

        ; set up the control pins for the EPROM
        ; start with all control pins HIGH (inactive) except VPP which is LOW (5V)
        ; default state: VPP=0 (5V), PGM=1, CE=1, OE=1 (read mode)
        LDAA    PORTA,X     
        ORAA    #%01101000  ; set OE, CE, PGM high
        ANDA    #%11101111  ; set VPP low
        STAA    PORTA,X     

        ; set up serial communication (SCI)
        ; configure for 9600 baud rate (based on 8MHz crystal / 2MHz E-clock)
        LDAA    #$30        ; set the baud rate divisors: SCP1:0=11 (div 13), SCR2:0=000 (div 1)
        STAA    BAUD,X
        LDAA    #$0C        ; turn on transmit and receive
        STAA    SCCR2,X

        ; ==================================================
        ; IMPORTANT: Wait here for about 1 second!
        ; This gives the Python script time to switch 
        ; the computer's baud rate to 9600.
        ; ==================================================
        JSR     LONG_DELAY
        ; ==================================================

        ; set up our counters before we start programming
        CLRA                ; A will track which address we're programming (starts at 0)

MAIN_PROG_LOOP:
        ; save address in B for safety
        TAB                 ; store address in B

        ; reset pulse counter for this byte
        PSHA
        LDAA    #0
        STAA    PULSE_COUNT
        PULA

        ; step 1: set address on Port B
        STAA    PORTB,X

        ; step 2: setup data on Port C (output mode)
        PSHA
        LDAA    #$FF        ; configure all bits as output
        STAA    DDRC,X
        LDAA    #DATA_BYTE  ; load test pattern ($AA)
        STAA    PORTC,X     ; drive data bus
        PULA

        ; step 3: enable high voltage (VPP=12.5V, VCC=6V)
        PSHA
        LDAA    PORTA,X
        ORAA    #VPROG_BIT  ; turn on VPP (PA4 high)
        STAA    PORTA,X
        PULA
        
        ; wait for VPP to rise (at least 2µs)
        NOP
        NOP

PULSE_RETRY_LOOP:
        ; step 4: programming pulse sequence
        ; PGM low -> CE low (pulse starts) -> CE high (pulse ends) -> PGM high
        
        PSHA
        LDAA    PORTA,X
        ANDA    #%11110111  ; pull PGM low (bit 3)
        STAA    PORTA,X
        
        ANDA    #%11011111  ; pull CE low (bit 5) - START PULSE
        STAA    PORTA,X
        
        JSR     DELAY_1MS   ; wait for 1ms
        
        ORAA    #CE_BIT     ; pull CE high (bit 5) - END PULSE
        STAA    PORTA,X
        
        ORAA    #PGM_BIT    ; pull PGM high (bit 3)
        STAA    PORTA,X
        PULA

        ; step 5: verify (read byte back)
        ; switch Port C to input mode
        PSHA
        LDAA    #$00
        STAA    DDRC,X
        PULA

        ; enable read mode (CE low, OE low)
        PSHA
        LDAA    PORTA,X
        ANDA    #%10011111  ; clear bits 5 and 6
        STAA    PORTA,X
        NOP                 ; wait for data to appear
        NOP
        
        LDAA    PORTC,X     ; read data from EPROM
        CMPA    #DATA_BYTE  ; compare with expected value
        BEQ     BYTE_VERIFIED
        
        ; step 6: verify failed - setup for retry
        ; disable read (CE/OE high)
        LDAA    PORTA,X
        ORAA    #%01100000
        STAA    PORTA,X
        PULA                ; restore address A
        
        ; reset Port C to output for next retry
        PSHA
        LDAA    #$FF
        STAA    DDRC,X
        LDAA    #DATA_BYTE
        STAA    PORTC,X
        PULA

        INC     PULSE_COUNT ; increment retry counter
        LDAA    PULSE_COUNT
        CMPA    #MAX_RETRIES
        BNE     PULSE_RETRY_LOOP ; retry if under limit
        
        SWI                 ; fatal error - defective chip

BYTE_VERIFIED:
        ; disable read (CE/OE high)
        LDAA    PORTA,X
        ORAA    #%01100000
        STAA    PORTA,X
        PULA                ; restore address A

        ; step 7: over-program pulse (3ms) for data retention
        JSR     OVER_PROGRAM
        
        ; step 8: disable high voltage (back to 5V)
        PSHA
        LDAA    PORTA,X
        ANDA    #%11101111  ; turn off VPP (PA4 low)
        STAA    PORTA,X
        PULA
        
        ; send feedback to PC
        PSHA
        LDAA    #DATA_BYTE
        JSR     SEND_SERIAL
        PULA

        INCA                ; move to next address
        CMPA    #25         ; have we programmed all 25 bytes?
        BNE     MAIN_PROG_LOOP

        SWI                 ; all done!

; subroutine to send whatever's in A out the serial port
SEND_SERIAL:
        BRCLR   SCSR,X #$80 SEND_SERIAL ; wait here until transmit buffer is empty (TDRE bit)
        STAA    SCDR,X                  ; write our byte to the transmit register
        RTS

; subroutine for a long delay (roughly 1 second)
LONG_DELAY:
        PSHY                ; save Y so we don't mess it up
        PSHX                ; save X too (important: we need X = $1000 later!)
        
        LDY     #$0010      ; outer loop runs 16 times
DELAY_OUTER:
        LDX     #$FFFF      ; inner loop runs 65535 times each
DELAY_INNER:
        DEX
        BNE     DELAY_INNER ; keep counting down X until it hits zero
        DEY
        BNE     DELAY_OUTER ; keep going through Y until it hits zero too
        
        PULX                ; restore X back to $1000
        PULY                ; restore Y
        RTS

; subroutine for over-programming (3ms pulse for data retention)
OVER_PROGRAM:
        ; re-drive data on Port C (output mode)
        PSHA
        LDAA    #$FF
        STAA    DDRC,X
        LDAA    #DATA_BYTE
        STAA    PORTC,X
        
        ; ensure VPP is still high
        LDAA    PORTA,X
        ORAA    #VPROG_BIT
        STAA    PORTA,X
        
        ; assert PGM low
        ANDA    #%11110111
        STAA    PORTA,X
        
        ; pulse CE low
        ANDA    #%11011111
        STAA    PORTA,X
        
        ; wait for 3ms (three 1ms delays)
        JSR     DELAY_1MS
        JSR     DELAY_1MS
        JSR     DELAY_1MS
        
        ; end pulse (CE high, PGM high)
        ORAA    #CE_BIT
        ORAA    #PGM_BIT
        STAA    PORTA,X
        
        ; set Port C back to input
        LDAA    #$00
        STAA    DDRC,X
        PULA
        RTS

; subroutine for 1 millisecond delay
DELAY_1MS:
        PSHY
        LDY     #500            ; 500 loops * ~4 cycles = 2000 cycles at 2MHz = 1ms
D1:     DEY
        BNE     D1
        PULY
        RTS