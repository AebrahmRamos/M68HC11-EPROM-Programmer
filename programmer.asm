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