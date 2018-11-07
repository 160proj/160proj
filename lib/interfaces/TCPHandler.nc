#include "../../includes/packet.h"

interface TCPHandler {
    command void startServer(uint16_t port, uint16_t* seq);
    command void startClient(uint16_t dest, uint16_t srcPort, uint16_t destPort, uint16_t transfer, uint16_t* seq);
    command void closeClient(uint16_t dest, uint16_t srcPort, uint16_t destPort);
    command void recieve(pack* msg);
    event void route(pack* msg);
}
