#include "../../includes/packet.h"

interface RoutingHandler {
    command void start(uint16_t* seq);
    command void send(pack* msg);
    command void recieve(pack* routing_packet);
    command void updateNeighbors(uint32_t* neighbors, uint16_t numNeighbors);
    command void printRoutingTable();
}