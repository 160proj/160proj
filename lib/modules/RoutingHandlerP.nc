#include "../../includes/route.h"
#include "../../includes/packet.h"

module RoutingHandlerP {
    provides interface RoutingHandler;

    uses interface Hashmap<Route> as RoutingTable;
    uses interface SimpleSend as Sender;
}

implementation {

    /**
     * Add route to routing table
     */
    void addEntry(uint16_t src, Route route) {
        if (route.dest == TOS_NODE_ID) {
            return;
        }

        route.cost += 1;
        route.next_hop = src;
        route.TTL = MAX_ROUTE_TTL;

        if (route.cost > 16) {
            route.cost = 16;
        }

        call RoutingTable.insert(route.dest, route);
    }

    /**
     * Handles merging new routes into the routing table
     */
    void mergeRoute(Route* newRoute, uint8_t src) {
        uint32_t* routes = call RoutingTable.getKeys();
        uint16_t size = call RoutingTable.size();
        uint16_t i;

        // Attempted poison-reverse
        if (src == newRoute->next_hop && newRoute->cost >= MAX_ROUTE_TTL) {
            addEntry(src, *newRoute);
            return;
        }

        for (i = 0; i < size; i++) {
            Route route = call RoutingTable.get(routes[i]);
            if (newRoute->dest == route.dest) {
                if (newRoute->cost + 1 < route.cost) {
                    /* found a better route */
                    break;
                } else if (newRoute->next_hop == route.next_hop) {
                    /* metric for current next_hop may have changed */
                    break;
                } else {
                    /* route is uninteresting, ignore it */
                    return;
                }
            }
        }

        addEntry(src, *newRoute);
    }

    /**
     * Given a list of new routes, updates the routing table
     */
    void updateRoutingTable(Route* newRoute, uint16_t numNewRoutes, uint16_t src) {
        uint16_t i;

        for (i = 0; i < numNewRoutes; i++) {
            mergeRoute(&newRoute[i], src);
        }
    }

    /**
     * Sends a distance vector table to provided neighbor
     * Requires sequence number for packet
     */
    void sendDV(uint16_t neighbor) {
        uint32_t* routes = call RoutingTable.getKeys();
        uint16_t size = call RoutingTable.size();
        uint16_t i = 0;
        pack msg;

        msg.src = TOS_NODE_ID;
        msg.dest = 1;
        msg.TTL = 1;
        msg.protocol = PROTOCOL_DV;
        msg.seq = 1;

        for (i = 0; i < size; i++) {
            Route route = call RoutingTable.get(routes[i]);

            msg.dest = routes[i];
            memset(&msg.payload, '\0', PACKET_MAX_PAYLOAD_SIZE);
            memcpy(&msg.payload, &route, ROUTE_SIZE);

            call Sender.send(msg, neighbor);
        }
    }

    /**
     * Sends given packet based on the routing table's next hop value
     */
    command void RoutingHandler.send(pack* msg) {
        Route route;

        if (!call RoutingTable.contains(msg->dest)) {
            dbg(ROUTING_CHANNEL, "Cannot send packet from %d to %d: no connection\n", msg->src, msg->dest);
            return;
        }

        route = call RoutingTable.get(msg->dest);

        if (route.cost > 15) {
            dbg(ROUTING_CHANNEL, "Cannot send packet from %d to %d: cost infinity\n", msg->src, msg->dest);
            return;
        }
        
        dbg(ROUTING_CHANNEL, "Routing Packet: src: %d, dest: %d, seq: %d, next_hop: %d, cost: %d\n", msg->src, msg->dest, msg->seq, route.next_hop, route.cost);

        call Sender.send(*msg, route.next_hop);
    }

    /**
     * Initializes the routing table with existing neighbors
     * Called with timer
     */
    command void RoutingHandler.init(uint32_t* neighbors, uint16_t size) {
        uint32_t* routes = call RoutingTable.getKeys();
        uint16_t numRoutes = call RoutingTable.size();
        uint16_t i;

        // Invalidates missing neighbors
        for (i = 0; i < numRoutes; i++) { 
            Route route = call RoutingTable.get(routes[i]);
            if (route.cost == 1) {
                route.cost = MAX_ROUTE_TTL;
                addEntry(routes[i], route);
                sendDV(AM_BROADCAST_ADDR);
            }
        }

        // Adds neighbors to routing table
        for (i = 0; i < size; i++) {
            Route route;
            route.cost = 0;
            route.dest = neighbors[i];
            addEntry(neighbors[i], route);
        }
    }

    /**
     * Called by timer running periodic update
     */
    command void RoutingHandler.update() {
        uint32_t* routes = call RoutingTable.getKeys();
        uint16_t size = call RoutingTable.size();
        uint16_t i;

        // Remove stagnant routes
        for (i = 0; i < size; i++) {
            Route route = call RoutingTable.get(routes[i]);
            route.TTL--;

            // TTL Expired: Set cost to infinty and broadcast
            if (route.TTL == 0 && route.cost < MAX_ROUTE_TTL) {
                route.cost = MAX_ROUTE_TTL;
                route.TTL = 5;
                call RoutingTable.insert(route.dest, route);
                dbg(ROUTING_CHANNEL, "TTL of %d expired: broadcasting cost of %d\n", route.dest, route.cost);
                

            // Garbage collection
            } else if (route.TTL == 0 && route.cost >= MAX_ROUTE_TTL) {
                dbg(ROUTING_CHANNEL, "Garbage collecting %d\n", route.dest);
                call RoutingTable.remove(route.dest);
        
            // TTL is fine
            } else {
                call RoutingTable.insert(route.dest, route);
            }
        }
        
        sendDV(AM_BROADCAST_ADDR);
    }

    /**
     * Called when node recieves a distance vector packet
     */
    command void RoutingHandler.distanceVectorUpdate(pack* route_pack) {
        uint16_t num_routes = route_pack->seq;
        Route routes[num_routes];
        uint16_t i;

        for (i = 0; i < num_routes; i++) {
            memcpy(&routes[i], (&route_pack->payload) + i, ROUTE_SIZE);
        }

        updateRoutingTable(routes, num_routes, route_pack->src);
    }

    /**
     * Called by simulation
     * Prints the routing table in 'destination, next hop, cost' format
     */
    command void RoutingHandler.printRouteTable() {
        uint32_t* routes = call RoutingTable.getKeys();
        uint16_t size = call RoutingTable.size();
        uint16_t i;

        dbg(GENERAL_CHANNEL, "--- dest\tnext hop\tcost ---\n");
        for (i = 0; i < size; i++) {
            Route route = call RoutingTable.get(routes[i]);
            dbg(GENERAL_CHANNEL, "--- %d\t\t%d\t\t\t%d\n", route.dest, route.next_hop, route.cost);
        }
        dbg(GENERAL_CHANNEL, "--------------------------------\n");
    }

    /**
     * Misc debug command
     */
    command void RoutingHandler.debug() {
        dbg(ROUTING_CHANNEL, "Size: &d\n", call RoutingTable.size());
    }
}