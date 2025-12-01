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
VPROG_BIT EQU   %00100000   ; bit 5 for VPP control
OE_BIT    EQU   %01000000   ; bit 6 for output enable
CE_BIT    EQU   %00100000   ; bit 5 for chip enable

; variable storage in RAM
PULSE_COUNT EQU $0100       ; counter for programming pulses

        ORG     $0000       ; start of program in RAM

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
        ; start with CE (bit 5) and OE (bit 6) set HIGH so they're inactive
        LDAA    PORTA,X     
        ORAA    #%01100000  
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

        ; set up our counters before we start reading
        CLRA                ; A will track which address we're reading (starts at 0)
        LDAB    #25         ; B counts how many bytes left to read (25 total)

READ_LOOP:
        ; step 1: tell the EPROM which address we want to read from
        STAA    PORTB,X     

        NOP                 ; wait a moment for things to stabilize

        ; step 2: turn on the EPROM by pulling CE and OE low
        PSHA                ; save our address for later
        LDAA    PORTA,X     
        ANDA    #%10011111  ; clear bits 5 and 6 to pull them low
        STAA    PORTA,X     
        PULA                ; get our address back

        NOP                 ; give the EPROM time to put the data on the bus
        NOP

        ; step 3: read the byte from the EPROM
        PSHA                ; save our address first (we need A for the data)
        LDAA    PORTC,X     ; read the data byte from Port C into A
        
        ; ==============================================
        ; step 4: send what we just read to the computer
        ; ==============================================
        JSR     SEND_SERIAL ; call subroutine to transmit the byte
        ; ==============================================

        PULA                ; bring back our address counter

        ; step 5: turn off the EPROM by setting CE and OE back to high
        PSHA
        LDAA    PORTA,X
        ORAA    #%01100000  
        STAA    PORTA,X
        PULA

        ; step 6: move to the next byte
        INCA                ; go to next address
        DECB                ; one less byte to read
        BNE     READ_LOOP   ; keep going if we're not done yet

        SWI                 ; all done! stop heredone! stop here

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

; subroutine to program a single byte to the EPROM
; assumes: data to program is in stack at 0,Y
; assumes: address to program is in stack at 1,Y
PROGRAM_BYTE:
        LDAA    #1              ; start with pulse count = 1
        STAA    PULSE_COUNT     ; store it

PULSE_LOOP:
        ; step 1: set data and address on the EPROM pins
        LDAA    1,Y             ; load address from stack
        STAA    PORTB,X         ; put it on the address lines
        
        ; set Port C to output mode
        PSHA
        LDAA    #$FF            ; configure all bits as output
        STAA    DDRC,X
        PULA
        
        LDAA    0,Y             ; load data from stack
        STAA    PORTC,X         ; put it on the data lines

        ; step 2: apply a 1ms programming pulse
        ; turn on VPP, keep OE high, pull CE low
        LDAA    PORTA,X
        ORAA    #VPROG_BIT      ; turn on VPP
        ORAA    #OE_BIT         ; keep OE high (disable output)
        ANDA    #%11011111      ; pull CE low (enable chip)
        STAA    PORTA,X
        
        JSR     DELAY_1MS       ; wait for 1ms

        ; end the pulse by pulling CE high
        LDAA    PORTA,X
        ORAA    #CE_BIT         ; pull CE high (disable chip)
        STAA    PORTA,X

        ; step 3: verify the byte by reading it back
        ; set Port C to input mode so we can read
        PSHA
        LDAA    #$00
        STAA    DDRC,X
        PULA

        ; turn on read mode (CE low, OE low)
        LDAA    PORTA,X
        ANDA    #%10011111      ; pull CE and OE low for reading
        STAA    PORTA,X
        
        NOP                     ; wait for data to appear
        
        LDAA    PORTC,X         ; read the data we just programmed
        CMPA    0,Y             ; compare it with what we wanted
        BEQ     VERIFY_PASS     ; if they match, we're done with this byte!

        ; step 4: verify failed - we need to retry
        ; reset the control pins to inactive
        LDAA    PORTA,X
        ORAA    #%01100000      ; pull CE and OE back high
        STAA    PORTA,X

        INC     PULSE_COUNT     ; try again (increment pulse count)
        LDAA    PULSE_COUNT
        CMPA    #MAX_RETRIES    ; have we tried too many times?
        BGT     PROG_FAIL       ; if yes, the EPROM might be defective
        
        BRA     PULSE_LOOP      ; go back and try another 1ms pulse

VERIFY_PASS:
        ; step 5: over-program with a 3ms pulse to ensure proper programming
        ; set Port C back to output and restore the data
        LDAA    #$FF
        STAA    DDRC,X
        LDAA    0,Y
        STAA    PORTC,X

        ; apply the over-program pulse (VPP on, CE low, OE high)
        LDAA    PORTA,X
        ORAA    #VPROG_BIT
        ORAA    #OE_BIT
        ANDA    #%11011111      ; CE low
        STAA    PORTA,X

        JSR     DELAY_1MS       ; pulse for 3ms total
        JSR     DELAY_1MS
        JSR     DELAY_1MS

        ; end the over-program pulse
        LDAA    PORTA,X
        ORAA    #CE_BIT         ; pull CE high
        STAA    PORTA,X
        
        RTS                     ; done! return to caller

PROG_FAIL:
        ; byte could not be programmed after 25 retries
        SWI                     ; stop and signal error

; subroutine for 1 millisecond delay
DELAY_1MS:
        PSHY
        PSHX
        
        LDY     #$0004          ; approx. 1ms at 2MHz E-clock
DELAY_1MS_OUTER:
        LDX     #$FFFF
DELAY_1MS_INNER:
        DEX
        BNE     DELAY_1MS_INNER
        DEY
        BNE     DELAY_1MS_OUTER
        
        PULX
        PULY
        RTS