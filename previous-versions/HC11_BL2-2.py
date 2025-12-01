# Program arguments:  -c /dev/ttyUSB0 -i BOOTLOAD.S19

import sys, getopt
import serial
import time

def read_eprom_data(ser):
    print("\n-------------------------------------------------")
    print(f"Waiting for 25 bytes from EPROM...")
    print(f"(Will timeout after {ser.timeout} seconds...)\n")
    # time.sleep(5)
    
    try:
        # Ask the serial port to read 25 bytes
        data = ser.read(25)

        if not data:
            print("ERROR: Read timeout. No data received from HC11.")
            print("Check your HC11 wiring, power, and program.")
            return

        if len(data) < 25:
            print(f"WARNING: Received only {len(data)} bytes, expected 25.")

        print("--- EPROM Data Received (Hex) ---")
        
        # Print the data in a nice hex format
        hex_string = ""
        for i, byte in enumerate(data):
            hex_val = f"0x{byte:02X}"
            hex_string += f"{hex_val} "
            if (i + 1) % 8 == 0:
                hex_string += "\n" # Newline every 8 bytes
        
        print(hex_string)
        print("\n-------------------------------------------------")

    except serial.SerialException as e:
        print(f"ERROR: Serial communication error: {e}")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")

def main(argv):
    comport = ''
    s19file = ''
    loopback = False;
    try:
        opts, arg = getopt.getopt(argv,"hlc:i:",["port","ifile="])
    except getopt.GetoptError:
        print ('HC11_bootload -c <COM_port> -i <s19_inputfile>')
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print ('HC11_bootload -c <COM_port> -i <s19_inputfile>')
            sys.exit()
        elif opt == '-l':
            loopback = True
        elif opt in ("-c", "--port"):
            comport = arg
        elif opt in ("-i", "--ifile"):
            s19file = arg

    print('HC11 Bootload Mode RAM Loader, v0.2 Clem Ong  note: this ver limited to 256-byte progs.')
    print()
    print('Program will use', comport)
    print('Parsing ', s19file,':', sep = '')

    ser = serial.Serial (port = comport, baudrate = 1200, timeout = 6.5)   # linux: /dev/tty/usb…  Windows: COMx
#    print (comport, s19file)
# set timeout and write_timeout to 20s

    machine_code = bytearray(256);
    i = 0
    while i < 256:
        machine_code[i] = 0
        i += 1

# parse the S19 file, converting the ASCII into 8-bit numbers (bytes) and stuffing it into the array

    f = open(s19file)
    line= f.readline()
#    print (line)
    j = 0
    while line: 
  # parse the line left to right… 
  # case first char is 0, 1 or 9.  We are interested only with lines that begin with "1". 
  # if "1" then 
  # byte count, 16 bit address, followed by data… (remember - this is represented as HEX digits, written as ASCII), then checksum
  # Maybe we can just ignore 16-bit address (4 hex digits) since this is loaded into RAM and will always start at 0000?
  #     NOTE: CANNOT IGNORE ADDRESS.  
  # S1BBaaaaDDDDDDDDC <— B byte count aaaa address D - data byte C checksum 
        if line[0:2] == 'S1':
            bcount = int(line[2:4],16)
            dcount = bcount-3    # 2 bytes for address, 1 byte for checksum. Whatever is left is the number of bytes for data.
            i = 0
            j = int(line[4:8],16)
            k = 0
#            print (line)
            print ("@", hex(j), end = ":")
            while k < (dcount):
                machine_code[j] = int(line[i+8:i+10],16)  # not sure if int is automatically converted to byte!! <it does>
                byte = hex(machine_code[j])[-2:]
                if byte[0] == 'x':
                    byte = "0" + byte[-1:]
                print (byte, end =' ')
                i += 2
                j += 1
                k += 1
        line = f.readline()
        print ()
    f.close()   # close file
    
    print ('Input S19 file parsed. ', end = ' ')
    ser.write (b"\x00")
    print ('Press the RESET button of the HC11 board now.')
    input('Program is paused - press Enter on keyboard after HC11 RESET.')
    time.sleep(1.0)
# send to the HC11
# but first tell HC11 to go into 1200baud by sending it an FFh. HC11 decides on baud rate depending what it decodes the FF to. 
    print('Serial coms to HC11: Sending 0xFF and the rest of the code... ')
    ser.write(b"\xff")
#    time.sleep(0.1)             # this is supposed to give the HC11 more than enough time to reprogram its serial comms to 1200 baud.
#    print('0xFF sent; now sending RAM program bytes...')
    ser.write(machine_code)  # send the whole 256-byte array to the HC11
    print()

# Read back what the HC11 (should have) sent back, which is an echo of what it received:
    print("Waiting for echoback from HC11.  If you don't see anthing on screen, something is wrong...")
    
    byte = ser.read()   # HC11 will not echo back the 0xFF sync byte, but a serial loopback will. 
    if not byte:
        print ('HC11 is not sending anything back - aborting.')
    else:
        if loopback:
            print('Sync:', hex(ord(byte)))
            j = 256
        else:
            print (hex(ord(byte)), end = ' ')
            j = 255
        
        # Modified - - - - - - - - - - - - - - - - - - - - - - - - - - -
        # Add a flag to track if echo was successful
        echo_success = True
        
        while j > 0:
            byte = ser.read()
            if byte:
                print (hex(ord(byte)), end = ' ')
                j -= 1
            else:
                print ("Error in received data - aborting.")
                j = 0
                echo_success = False # Echo failed
        
        print('\n\n')
        
        # Modified - - - - - - - - - - - - - - - - - - - - - - - - - - -
        # If echo was successful, switch baud rate and read EPROM data
        if echo_success:
            print ('Done - HC11 should be running your machine code in RAM now.')
            print ('Switching to 9600 baud to listen for EPROM data...')
            
            # Close and re-open port at 9600 baud
            ser.close()
            ser.baudrate = 9600
            ser.timeout = 15.0  # New timeout for reading EPROM data
            ser.open()
            
            # Call the new function to read the 25 bytes
            read_eprom_data(ser)
            
        else:
            print('Echo failed. Will not attempt to read EPROM data.')
            
    ser.close()

# Upon receiving 256th byte, older HC11s will automatically stop RX and do a jump to RAM location 0000h. 
#    on newer devices, not sending anything for 4 character time units will terminate RX mode and jump to 0000h. 

if __name__ == "__main__":
    main(sys.argv[1:])