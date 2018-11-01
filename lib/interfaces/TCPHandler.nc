#include "../../includes/packet.h"

interface TCPHandler {
    command void start();
    command void send(uint8_t dest, uint8_t srcPort, uint8_t destPort, uint32_t transfer);
    command void recieve(pack* msg);
}
