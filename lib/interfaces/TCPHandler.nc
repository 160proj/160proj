#include "../../includes/packet.h"

interface TCPHandler {
    command void startServer(uint16_t port);
    command void startClient(uint16_t dest, uint16_t srcPort, uint16_t destPort, uint16_t transfer);
    command void closeClient(uint16_t dest, uint16_t srcPort, uint16_t destPort);
    command void start();
    command void send(uint8_t dest, uint8_t srcPort, uint8_t destPort, uint32_t transfer);
    command void recieve(pack* msg, uint8_t dest, uint8_t srcPort, uint8_t destPort, uint32_t transfer);
}
