# M68HC11-EPROM-Programmer

## Part 1: EPROM Reader

### Overview

This project implements an EPROM reader using the M68HC11 microcontroller and a 2764 EPROM chip. The system reads the first 25 bytes of data stored in the EPROM and transmits it to a host computer via serial communication for display in both hexadecimal and ASCII formats.

### Hardware Configuration

The hardware setup maps the M68HC11 ports to the 2764 EPROM pins as follows:

- **Port B (PB0-PB7)**: Connected to EPROM address inputs A0-A7
- **Port C (PC0-PC7)**: Connected to EPROM data outputs Q0-Q7
- **Port A (PA5, PA6)**: Control signals for Chip Enable (CE) and Output Enable (OE)
- **Upper Address Lines (A8-A12)**: Grounded to restrict addressable space to the first 256 bytes

The EPROM operates with a 5V supply and has an access time of 180-250ns depending on the speed grade.

### Software Implementation

The system consists of two main components:

#### Assembly Program (programmer.asm)

The M68HC11 assembly program performs the following steps:

1. **Initialization**: Sets up the stack pointer and forces the device into single-chip mode
2. **Port Configuration**: Configures Port C as input and sets control pins to inactive (HIGH)
3. **Serial Setup**: Initializes the SCI (Serial Communication Interface) to 9600 baud
4. **Startup Delay**: Implements a `LONG_DELAY` routine to allow the bootloader time to switch baud rates
5. **Read Loop**: Iterates 25 times to:
   - Assert the address on Port B
   - Activate control signals (pull CE and OE LOW)
   - Read the data byte from Port C
   - Send the byte to the PC via `SEND_SERIAL` subroutine
   - Deactivate control signals (pull CE and OE HIGH)

#### Python Bootloader (HC11_BL-ASCII.py)

The modified bootloader script:

- Loads the assembly program into the HC11's RAM via serial at 1200 baud
- Switches the serial port to 9600 baud after successful echo-back
- Calls `read_eprom_data()` to receive and display the 25 bytes
- Displays output in hexadecimal format (8 bytes per line)
- Displays output in ASCII format (replaces non-printable characters with ".")

### Key Challenge: Baud Rate Synchronization

During initial testing, a race condition occurred where the HC11 began transmitting data before the bootloader could switch from 1200 to 9600 baud. This resulted in corrupted or "ghost" byte values.

**Solution**: Implemented the `LONG_DELAY` subroutine after baud rate configuration to waste CPU cycles, giving the bootloader sufficient time to reinitialize the serial connection at 9600 baud before the read loop begins.

### Results

The system successfully:

- Reads the first 25 bytes from the 2764 EPROM
- Transmits data error-free via serial communication
- Displays data in both hexadecimal and ASCII formats
- Handles the 0xFF value gracefully by displaying it as "." in ASCII output (since ASCII is a 7-bit standard supporting only values 0-127)

### Materials

- 1x M68HC11 Interface Board
- 1x 2764 EPROM
- 1x Breadboard
- 2x Power Supplies
- 5x 10Kohm Resistors
- 1x Oscilloscope
- 1x VOM (Voltmeter/Ohmmeter)
- 1x Computer System

### Usage

1. Assemble the assembly code into an S19 file
2. Run the bootloader script: `python HC11_BL-ASCII.py -c /dev/ttyUSB0 -i programmer.s19`
3. Press RESET on the HC11 board when prompted
4. The program will load, switch baud rates, and display the EPROM data

### Recommendations for Future Work

While the current implementation successfully resolves the baud rate race condition, it uses a fixed delay that is not deterministic. A more robust approach would implement a software handshake using interrupts, similar to TCP's three-way handshake. This would ensure 100% data synchronization without relying on timing assumptions that may fail on slower systems or under heavy CPU load.
