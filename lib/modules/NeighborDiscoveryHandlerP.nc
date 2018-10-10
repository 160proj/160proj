#include "../../includes/packet.h"

module NeighborDiscoveryHandlerP {
    provides interface NeighborDiscoveryHandler;

    uses interface SimpleSend as Sender;
    uses interface Hashmap<uint16_t> as Neighbors;
}

implementation {
    const uint16_t TIMEOUT_CYCLES = 5; // Number of missed replies before dropping a neighbor

    /**
     * Changes provided neighbor discovery packet into a neighbor discovery reply and sends it
     */
    void pingReply(pack* msg) {
        msg->src = TOS_NODE_ID;
        msg->protocol = PROTOCOL_PINGREPLY;
        call Sender.send(*msg, AM_BROADCAST_ADDR);
    }

    /**
     * Add a node to the list of neighbors
     * Signals the neighborListUpdated event if it is a new node
     */
    void addNeighbor(uint16_t src) {
        uint16_t i;
        uint32_t* neighbors;
        bool isNew = TRUE;
        
        call Neighbors.insert(src, TIMEOUT_CYCLES);
        neighbors = call NeighborDiscoveryHandler.getNeighbors();

        for (i = 0; i < call NeighborDiscoveryHandler.numNeighbors(); i++) {
            if (neighbors[i] == src) {
                isNew = FALSE;
                break;
            }
        }

        if (isNew) {
            signal NeighborDiscoveryHandler.neighborListUpdated();
        }
    }

    /**
     * Helper function for processing neighbor discovery packets
     * Neighbor discovery implemented with only ping and ping replies
     */
    void protocolHandler(pack* msg) {
        switch(msg->protocol) {
            case PROTOCOL_PING:
                dbg(NEIGHBOR_CHANNEL, "Neighbor discovery from %d. Adding to list & replying...\n", msg->src);
                addNeighbor(msg->src);
                pingReply(msg);
                break;

            case PROTOCOL_PINGREPLY:
                dbg(NEIGHBOR_CHANNEL, "Neighbor reply from %d. Adding to neighbor list...\n", msg->src);
                addNeighbor(msg->src);
                break;

            default:
                dbg(GENERAL_CHANNEL, "Unrecognized neighbor discovery protocol: %d\n", msg->protocol);
        }
    }

    /**
     * Removes 1 'cycle' from all the timeout values on the neighbor list
     * Removes the node ID from the list if the timeout drops to 0
     */
    void decrement_timeout() {
        uint16_t i;
        uint32_t* neighbors = call Neighbors.getKeys();

        // Subtract 1 'clock cycle' from all the timeout values
        for (i = 0; i < call Neighbors.size(); i++) {
            uint16_t timeout = call Neighbors.get(neighbors[i]);
            call Neighbors.insert(neighbors[i], timeout - 1);

            // Node stopped replying, drop it
            if (timeout - 1 <= 0) {
                call Neighbors.remove(neighbors[i]);
                signal NeighborDiscoveryHandler.neighborListUpdated();
            }
        }
    }

    /**
     * Creates packet used for neighbor discovery
     * Uses dest=AM_BROADCAST_ADDR as the method to detect a neighbor discovery packet
     */
    void createNeighborPack(pack* neighborPack, uint16_t seq) {
        neighborPack->src = TOS_NODE_ID;
        neighborPack->dest = AM_BROADCAST_ADDR;
        neighborPack->TTL = 1;
        neighborPack->seq = seq;
        neighborPack->protocol = PROTOCOL_PING;
        memcpy(neighborPack->payload, "Neighbor Discovery\n", 19);
    }

    /**
     * Sends out neighbor discovery packet with the sequence number passed to it
     */
    command void NeighborDiscoveryHandler.discover(uint16_t seq) {
        pack neighborPack;
        decrement_timeout();
        createNeighborPack(&neighborPack, seq);
        call Sender.send(neighborPack, AM_BROADCAST_ADDR);
    }

    /**
     * Called when node recieves neighbor discovery packet
     */
    command void NeighborDiscoveryHandler.recieve(pack* msg) {
        protocolHandler(msg);
    }

    /**
     * Returns list of neighbors. Pair with numNeighbors() to iterate
     */
    command uint32_t* NeighborDiscoveryHandler.getNeighbors() {
        return call Neighbors.getKeys();
    }

    /**
     * Returns the number of neighbors
     */
    command uint16_t NeighborDiscoveryHandler.numNeighbors() {
        return call Neighbors.size();
    }

    /**
     * Prints the list of neighbors for this node
     */
    command void NeighborDiscoveryHandler.printNeighbors() {
        uint16_t i;
        uint32_t* neighbors = call NeighborDiscoveryHandler.getNeighbors();

        dbg(GENERAL_CHANNEL, "--- Neighbors of Node %d ---\n", TOS_NODE_ID);
        for (i = 0; i < call NeighborDiscoveryHandler.numNeighbors(); i++) {
            dbg(GENERAL_CHANNEL, "%d\n", neighbors[i]);
        }
        dbg(GENERAL_CHANNEL, "---------------------------\n");
    }
}
