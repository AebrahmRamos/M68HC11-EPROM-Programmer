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

        ORG     $0000       ; Start of Program in RAM

START:
        LDS     #STACK      ; 1. Initialize Stack

        LDX     #REGBAS     ; 2. Load X with $1000 (Exp 8 Style)

        ; --- MODE FIX ---
        ; Force Single Chip Mode (MDA=0) but keep Boot ROM (RBOOT=1)
        LDAA    #$C0        
        STAA    HPRIO,X     ; Write to $103C

        ; --- CONFIGURE PORT C ---
        LDAA    #$00        ; Set Port C to INPUT
        STAA    DDRC,X      ; Write to $1007

        ; --- INITIALIZE CONTROL PINS ---
        ; CE (Bit 5) and OE (Bit 6) HIGH (Inactive)
        LDAA    PORTA,X     
        ORAA    #%01100000  
        STAA    PORTA,X     

        ; --- CONFIGURE SCI (SERIAL) ---
        ; Set to 9600 Baud (Assuming 8MHz Crystal / 2MHz E-Clock)
        LDAA    #$30        ; SCP1:0=11 (Div 13), SCR2:0=000 (Div 1)
        STAA    BAUD,X
        LDAA    #$0C        ; Enable Tx and Rx
        STAA    SCCR2,X

        ; ==================================================
        ; !!! CRITICAL FIX: STARTUP DELAY !!!
        ; We wait here for ~1 second to give the Python script 
        ; time to switch the PC's baud rate to 9600.
        ; ==================================================
        JSR     LONG_DELAY
        ; ==================================================

        ; --- INIT COUNTERS ---
        CLRA                ; A = Address Counter (starts at 0)
        LDAB    #25         ; B = Byte Counter (25 bytes)

READ_LOOP:
        ; 1. Send Address to EPROM (via Port B)
        STAA    PORTB,X     

        NOP                 ; Stability delay

        ; 2. Activate EPROM (CE/OE Low)
        PSHA                ; Save Address
        LDAA    PORTA,X     
        ANDA    #%10011111  ; Clear Bits 5 & 6
        STAA    PORTA,X     
        PULA                ; Restore Address

        NOP                 ; Access Time Delay
        NOP

        ; 3. Read Data from EPROM
        PSHA                ; Save Address (A) to Stack
        LDAA    PORTC,X     ; A now holds the DATA from EPROM
        
        ; ==============================================
        ; 4. SEND DATA TO PC
        ; ==============================================
        JSR     SEND_SERIAL ; Go send 'A' to the computer
        ; ==============================================

        PULA                ; Restore Address (A) from Stack

        ; 5. Deactivate EPROM (CE/OE High)
        PSHA
        LDAA    PORTA,X
        ORAA    #%01100000  
        STAA    PORTA,X
        PULA

        ; 6. Next Byte
        INCA                ; Increment Address
        DECB                ; Decrement Counter
        BNE     READ_LOOP   ; Loop

        SWI                 ; Stop

; --- SUBROUTINE: Send Accumulator A to Serial Port ---
SEND_SERIAL:
        BRCLR   SCSR,X #$80 SEND_SERIAL ; Wait until TDRE (Transmit Empty) is 1
        STAA    SCDR,X                  ; Send Data
        RTS

; --- SUBROUTINE: Long Delay (~1 Second) ---
LONG_DELAY:
        PSHY                ; Save Y register
        PSHX                ; Save X register (CRITICAL: We need X for REGBAS later)
        
        LDY     #$0010      ; Outer Loop Counter
DELAY_OUTER:
        LDX     #$FFFF      ; Inner Loop Counter (Max 65535)
DELAY_INNER:
        DEX
        BNE     DELAY_INNER ; Loop until X is 0
        DEY
        BNE     DELAY_OUTER ; Loop until Y is 0
        
        PULX                ; Restore X (Base Address $1000)
        PULY                ; Restore Y
        RTS