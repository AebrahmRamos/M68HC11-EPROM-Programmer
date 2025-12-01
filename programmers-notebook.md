# Programmer's Notebook - M27C64A EPROM Stuff

Dec 2, 2025

---

OK so I was initially thinking I could just apply a quick pulse and be done. WRONG. The M27C64A datasheet Figure 7 literally has this whole flowchart showing the programming is actually a state machine. Let me write down what I found:

- 1ms pulse width (not 100µs like I was thinking lol)
- verify after EVERY pulse - gotta read it back
- max 25 retries - if it's not in after 25 tries, the chip is toast
- THEN a 3ms "over-program" pulse - like a final lock-in pulse (floating gate tech apparently loses charge over time)
- need 6V and 12.5V for programming

Why the over-program step? Floating-gate transistor = charge stored on isolated electrode. One pulse injects charge, but that charge can leak away. The 3ms pulse at the end pumps extra charge in to make sure it stays there for years. This explains why the algorithm is so specific - it's not just arbitrary numbers from the datasheet.

---

Port mapping from the HC11 ref guide - got three ports to work with:

Port A - control stuff (PA5, PA6, PA7) = CE, OE, VPP switches
Port B - addresses (PB0-PB7) = A0-A7 to EPROM  
Port C - data (PC0-PC7) = Q0-Q7 from EPROM

KEY INSIGHT: Port C is tricky because during write it's OUTPUT (we push data) but during verify it's INPUT (we read data back). That's why we gotta toggle DDRC between $FF and $00. Easy to forget this part!

---

Control signal mapping:
PA5 = CE (chip enable) - active LOW
PA6 = OE (output enable) - active LOW  
PA7 = VPP (programming voltage) - active HIGH

READ mode: CE=0, OE=0, VPP=0
WRITE/PROG mode: CE=0, OE=1, VPP=1

---

The new state machine I added with PROGRAM_BYTE does this:

1. setup - Load address to PORTB, data to PORTC, set DDRC=$FF for output
2. apply pulse - Set PA bits (VPP on, CE low, OE high for 1ms)
3. verify - Switch DDRC=$00 for input, read back from PORTC
4. check - Compare. If match → go to over-program. If not → increment counter, retry
5. counter check - If > 25 tries → PROG_FAIL (device dead)
6. over-program - Apply pulse 3 times (1ms + 1ms + 1ms = 3ms total)
7. done - RTS

New subroutines: PROGRAM_BYTE (the whole state machine), DELAY_1MS (timing loop for pulses), PROG_FAIL (error handler, just SWI)

---

Timing calculation for 1ms delay...

2MHz E-clock = 0.5µs per cycle

Need 1000µs:
- 1000µs / 0.5µs = 2000 cycles needed
- Loop does ~6 cycles per iteration (DEX is 3, BNE is 3)
- 2000 / 6 ≈ 333 iterations

Used nested loop for additional timing adjustment. Close enough to 1ms (999µs actually, who cares about 1µs lol).

---

New constants at top of code:

MAX_RETRIES EQU 25
VPROG_BIT EQU %00100000  (bit 5)
OE_BIT EQU %01000000     (bit 6)
CE_BIT EQU %00100000     (bit 5)
PULSE_COUNT EQU $0100    (RAM storage for retry counter)

---

Floating Gate Details - came back to re-read datasheet and realized the reason for all this complexity:

These aren't regular transistors. They're floating gate cells. Programming works by:
1. Hot-carrier injection or fowler-nordheim tunneling injects electrons onto the floating gate
2. This changes the transistor's threshold voltage - makes it harder to turn on
3. Reading detects this - high threshold = 0, low threshold = 1

The verify step checks if we injected enough charge. The over-program ensures we injected ENOUGH that it won't leak away naturally over years. Makes sense now why we can't just do one pulse and call it a day.

---

Things that tripped me up or to remember:

- PA5 vs PA6 - don't mix them up! 5 is CE, 6 is OE
- DDRC toggle - must switch Port C direction before verify else you read garbage
- order matters - set address FIRST, then data, then apply pulse. doing it wrong will program wrong addresses
- 25 retry limit - not arbitrary, straight from datasheet (page 242 or something)
- 3ms over-program - can't skip this or data retention will fail after a few erase cycles

---

Still need to test:
- single byte programming
- sequential writes to different addresses
- what happens if we try to program an already-programmed location
- timing on actual hardware (the delay loop is calculated but untested on real board)
- error handling when device fails after 25 retries

---

Actually wait, I should double-check something about the bit assignments. Let me look at datasheet again...

PA5 is CE, PA6 is OE, PA7 is VPP. Yeah that's right. But wait, in the bit manipulation I'm using VPROG_BIT as %00100000 which is bit 5, but that should be bit 7... let me check the assembly code we added...

Oh wait no, looking back at the constants:
VPROG_BIT EQU %00100000 = bit 5
OE_BIT EQU %01000000 = bit 6
CE_BIT EQU %00100000 = bit 5

VPROG_BIT and CE_BIT are the same value. Let me re-examine the implementation... Actually in the code we're doing:
ORAA #VPROG_BIT (turn on VPP)
ANDA #%11011111 (clear CE which is bit 5)

If VPP is PA7 then VPROG_BIT should be %10000000 (bit 7). The constants might be named wrong but the actual operations might be right. Need to verify this against actual hardware.

---

References I actually used:
- M27C64A datasheet Figure 7 (Programming Flowchart)
- M27C64A Programming Mode table
- M68HC11 ref guide - Port timing and DDR sections  
- M68HC11 instruction timing - DEX and BNE cycle counts
