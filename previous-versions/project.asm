PORTA   EQU     $1000   ; Port A Address
PORTB   EQU     $1004   ; Port B Address
PORTC   EQU     $1003   ; Port C Address
DDRC    EQU     $1007   ; Data Direction C

BAUD    EQU     $102B
SCCR2   EQU     $102D
SCSR    EQU     $102E
SCDR    EQU     $102F

STACK   EQU     $00FF

        ORG     $0000       ; start of program in RAM

START:
        LDS     #STACK          ; init stack

        ; make sure Port C is set as input (it should default to this anyway)
        LDAA    #$00
        STAA    DDRC

        ; set up the control pins for the EPROM
        ; start with CE (bit 5) and OE (bit 6) set HIGH so they're inactive
        ; we manually read PORTA, set bits 5 & 6, and write back
        LDAA    PORTA           ; read current Port A
        ORAA    #%00110000      ; set bit 5 (CE) and bit 6 (OE) to 1
        STAA    PORTA           ; write back to Port A

        ; set up serial communication (SCI)
        LDAA    #$0D
        STAA    BAUD
        LDAA    #%00001000
        STAA    SCCR2

        ; set up our counters before we start reading
        CLRA                    ; A will track which address we're reading (starts at 0)
        LDAB    #25             ; B counts how many bytes left to read (25 total)

READ_LOOP:
        STAA    PORTB           ; step 1: tell the EPROM which address we want to read from
        NOP

        ; step 2: turn on the EPROM by pulling CE and OE low
        ; we must save A (address counter) before using A for port manipulation
        PSHA                    ; save our address for later
        LDAA    PORTA           ; read Port A
        ANDA    #%10011111      ; clear bit 5 and 6 (mask $9F)
        STAA    PORTA           ; write back (CE/OE now low)
        PULA                    ; get our address back
        NOP                     ; give the EPROM time to put the data on the busto put the data on the bus

        ; step 3: read the byte from the EPROM
        PSHA                    ; save our address first (we need A for the data)
        LDAA    PORTC           ; read the data byte from Port C into A
        
        ; step 4: turn off the EPROM by setting CE and OE back to high
        ; A currently holds the EPROM data, so we must save it
        PSHA                    ; save EPROM data to stack
        LDAA    PORTA           ; read Port A
        ORAA    #%01100000      ; set bit 5 and 6 high
        STAA    PORTA           ; write back
        PULA                    ; restore EPROM data into A
        
        ; step 5: send what we just read to the computer
        JSR     SEND_BYTE_SCI   ; call subroutine to transmit the byte

        ; step 6: move to the next byte
        PULA                    ; bring back our address counter (from step 3)
        INCA                    ; go to next address
        DECB                    ; one less byte to read
        BNE     READ_LOOP       ; keep going if we're not done yetwe're not done yet

DONE:
        BRA     DONE

; subroutine to send whatever's in A out the serial port
SEND_BYTE_SCI:
        PSHA
WAIT_SCI:
        LDAA    SCSR
        ANDA    #%10000000
        BEQ     WAIT_SCI
        PULA
        STAA    SCDR
        RTS