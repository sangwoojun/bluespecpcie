import ClientServer::*;
import Connectable::*;

typedef Bit#(64) DDR3Address;
typedef Bit#(512) DDR3Data;

// DDR3 Request
// Used for both reads and writes.
//
// To perform a read:
//  writeen should be 0
//  address contains the address to read from
//  datain is ignored.

// To perform a write:
//  writeen should be 'hFFFFFFFF (to write all bytes, or something else
//      nonzero to only write some of the bytes).
//  address contains the address to write to
//  datain contains the data to be written.
typedef struct {
    // writeen: Enable writing.
    // Set the ith bit of writeen to 1 to write the ith byte of datain to the
    // ith byte of data at the given address.
    // If writeen is 0, this is a read request, and a response is returned.
    // If writeen is not 0, this is a write request, and no response is
    // returned.
    Bit#(64) writeen;

    // Address to read to or write from.
    // The DDR3 is 64 bit word addressed, but in bursts of 8 64 bit words.
    // The address should always be a multiple of 8 (bottom 3 bits 0),
    // otherwise strange things will happen.
    // For example: address 0 refers to the first 8 64 bit words in memory.
    //              address 4 refers to the second 8 64 bit words in memory.
   //DDR3Address address;
   Bit#(64) address;

    // Data to write.
    // For read requests this is ignored.
    // Only those bytes with corresponding bit set in writeen will be written.
//    DDR3Data datain;
   Bit#(512) datain;
} DDRRequest deriving(Bits, Eq);

// DDR2 Response.
// Data read from requested address.
// There will only be a response if writeen was 0 in the request.
typedef Bit#(512) DDRResponse;

typedef Client#(DDRRequest, DDRResponse) DDR3Client;

typedef struct {
   //Bool rnw;
   Bit#(7) nBytes;
   //Bit#(7) firstNbytes;
   //Bool oneCmd;
   Bit#(64) addr;
   Bit#(512) data;
   Bit#(64) mask0;
   Bit#(64) mask1;
   //Bit#(64) mask1;
   } DRAMWrRequest deriving (Bits, Eq);



typedef struct {
   Bit#(7) nBytes;
   Bit#(64) addr;
   } DRAMRdRequest deriving (Bits, Eq);
