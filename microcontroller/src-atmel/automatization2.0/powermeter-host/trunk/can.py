"""
  Provide a simmple interface to connect to a cand (or compatible) CAN gateway

  Example:

    c = CANSocket(host, port)  # open connection to cand
    pkt = c.get_pkt()          # return raw CAN packet
    lpkt = LAPPacket(pkt)      # parse to LAPPacket
    print lpkt
"""

import socket
import errno
import struct

#=============================================================================
# Utility functions

def hexdump(data):
    """ Return the content of the given (byte-) array as a nice hex-string """
    ret = ""
    for c in data:
        ret += "%02x " % c
    return ret


#=============================================================================
# Exception class

class CANError(Exception):
    def __init__(self, reason):
        self.reason = reason
    
    def __repr__(self):
        return repr(self.reason)

#=============================================================================
# Packet types / parsers

class ParseException(Exception):
    pass

def unpack_gwpacket(arr):
    """ Represents a packet as its transmitted over can-tcp or can-uart """
    if len(arr) < 1:
        raise ParseException()
    cmd = arr[0]
    payload = arr[1:]

    if cmd == 0x11:
        return LAPPacket(arr=payload)
    elif cmd == 0x19:
        pkt = ControlPacket("PSTATS", arr=payload)

        # Unpack content
        if len(payload) != 16:
            raise ParseException("Error unpacking PSTATS")
        pkt.rx_pkts, pkt.tx_pkts, pkt.rx_bytes, pkt.tx_bytes = struct.unpack("<IIII", str(payload))
        return pkt
    elif cmd == 0x1b:
        pkt = ControlPacket("POWER_DRAW", arr=payload)

        # Unpack content
        if len(payload) != 8:
            raise ParseException("Error unpacking POWER_DRAW")
        u_adc, i_adc, ref, gnd = struct.unpack("<HHHH", str(payload))

        # From ADC values to volts
        U_REF = 5.0
        ADC_RES = 1<<10
        DIVIDER_R1 = 2700
        DIVIDER_R2 = 1000
        SHUNT_R = 0.01
        SHUNT_AMP = 10
        u = (u_adc * U_REF / ADC_RES) * (DIVIDER_R1 + DIVIDER_R2) / DIVIDER_R2
        i = (i_adc * U_REF / ADC_RES) / (SHUNT_AMP * SHUNT_R)
            
        pkt.u = u
        pkt.i = i
        return pkt

    print "Unknown packet from gateway: cmd=0x%02x, payload=%s" % (cmd, hexdump(payload))
    return None


class ControlPacket:
    """ A control packet from or to a can gateway """
    def __init__(self, id, arr=None):
        self.id = id
        self.payload = arr

    def __str__(self):
        return "ControlPacket: %s, payload: %s" % (self.id, hexdump(self.payload))
        

class LAPPacket:
    """ A single LAP Packet """
    def __init__(self, arr=None):
        self.sa = 0
        self.sp = 0
        self.da = 0
        self.dp = 0
        self.data = bytearray("")
        self.dlc = len(self.data)

        if arr is not None:
            self.from_array(arr)

    def from_array(self, arr):
        """ Parse packet from RAW (byte-)array """
        if len(arr) < 4:
            return
        self.da = arr[0]
        self.sa = arr[1]
        self.dp = ((arr[2] & 0x60) >> 1) + (arr[2] & 0x0f)
        self.sp = ((arr[3] & 0x1f) << 1) + ((arr[2] & 0x80) >> 7)
        self.data = arr[5:]
        self.dlc = len(self.data)

    def to_array(self):
        return None

    def __str__(self):
        return "LAPPacket: %02x:%02x -> %02x:%02x: %s" % (self.sa, self.sp, self.da, self.dp, hexdump(self.data))

#=============================================================================
# Connection to a CAN gateway (cand)

class CANSocket:
    """ Connection to a cand """
    def __init__(self, host="10.0.1.2", port=2342):
        BUFFER_SIZE = 1024

        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.connect((host, port))
            s.setblocking(0)
        except socket.error as err:
            raise CANError("Could not connect")

        self.sock = s
        self.buf = bytearray("")

    def close(self):
        self.sock.close()

    def dequeue_pkt(self):
        buf = self.buf

        # Is there something at all?
        if len(buf) < 3:
            return None

        # Did we receive a full packet?
        l = buf[0]
        if len(buf)-2 < l:
            return None

        # Dequeue packet
        next = l+2
        payload = buf[1:next]
        self.buf = buf[next:]

        # Parse und return payload
        return unpack_gwpacket(payload)


    def get_pkt_nb(self):
        """ Receive a CAN packet; non-blocking.

            If there is no complete CAN packet to return, this function
            returns Null.
        """
        s = self.sock
        buf = self.buf

        pkt = self.dequeue_pkt()

        if pkt is not None:
            return pkt

        # Try to receive something
        s.setblocking(0)

        try:
            data = s.recv(1024)
        except socket.error as err:
            if err.errno == errno.EWOULDBLOCK or err.errno == errno.EAGAIN:
                return None
            else:
                raise err

        if len(data) == 0:
            raise CANError("Connection lost")
        buf += bytearray(data)

        return self.dequeue_pkt()


    def get_pkt(self):
        """ Receive a CAN packet; blocking.
        """
        s = self.sock
        buf = self.buf

        s.setblocking(1)

        pkt = self.dequeue_pkt()
        while pkt is None:
            # Receive something
            data = self.sock.recv(1024)
            if len(data) == 0:
                raise CANError("Connection lost")
            self.buf += bytearray(data)
            pkt = self.dequeue_pkt()

        return pkt
