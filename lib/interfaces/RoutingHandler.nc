#include "../../includes/packet.h"

interface RoutingHandler {
    command void init(uint32_t* neighbors, uint16_t numNeighbors);
    command void send(pack* msg);
    command void distanceVectorUpdate(pack* route_pack);
    command void update(uint32_t* neighbors, uint16_t numNeighbors);
    command void printRouteTable();
    command void debug();
}