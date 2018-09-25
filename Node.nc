/*
* ANDES Lab - University of California, Merced
* This class provides the basic functions of a network node.
*
* @author UCM ANDES Lab
* @date   2013/09/03
*
*/
#include <Timer.h>
#include <stdio.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"

module Node{
    uses interface Boot;

    uses interface SplitControl as AMControl;
    uses interface Receive;

    uses interface SimpleSend as Sender;

    uses interface CommandHandler;

    uses interface Timer<TMilli> as NeighborTimer;
    uses interface Random as Random;
    
    uses interface Hashmap<uint16_t> as Neighbors;

    uses interface FloodingHandler;
}

implementation{
    // Global Variables
    const uint16_t TIMEOUT_CYCLES = 3;  // # of timer 'cycles' before neighbor is removed from neighbor list
    pack sendPackage;                   // Generic packet used to hold the next packet to be sent
    uint16_t current_seq = 0;           // Sequence number of packets sent by node

    // Prototypes
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

    /* Project 1 */
    void pingReply(pack* msg);
    bool isDuplicate(uint16_t node_id, uint16_t sequence_num);
    void decrement_timeout();
    void pingHandler(pack* msg);
    void neighborDiscoveryHandler(pack* msg);
    uint16_t randNum(uint16_t min, uint16_t max);
    /* ********* */

    /**
     * Called when the node is started
     * Initializes/starts necessary services
     */
    event void Boot.booted(){
        call AMControl.start();
        call NeighborTimer.startPeriodic(randNum(1000,2000));

        dbg(GENERAL_CHANNEL, "Booted\n");
    }

    /**
     * Starts radio, called during boot
     */
    event void AMControl.startDone(error_t err){
        if (err == SUCCESS) {
            dbg(GENERAL_CHANNEL, "Radio On\n");
        } else {
            //Retry until successful
            call AMControl.start();
        }
    }

    event void AMControl.stopDone(error_t err){}

    /**
     * Helper function for processing ping packets
     * Only protocols needed are ping and ping reply
     */
    // TODO: Move to protocol handler module
    void pingHandler(pack* msg) {
        switch(msg->protocol) {
            case PROTOCOL_PING:
                dbg(GENERAL_CHANNEL, "--- Ping recieved from %d\n", msg->src);
                dbg(GENERAL_CHANNEL, "--- Packet Payload: %s\n", msg->payload);
                dbg(GENERAL_CHANNEL, "--- Sending Reply...\n");
                pingReply(msg);
                break;
                    
            case PROTOCOL_PINGREPLY:
                dbg(GENERAL_CHANNEL, "--- Ping reply recieved from %d\n", msg->src);
                break;
                    
            default:
                dbg(GENERAL_CHANNEL, "Unrecognized ping protocol: %d\n", msg->protocol);
        }
    }

    /**
     * Helper function for processing neighbor discovery packets
     * Neighbor discovery implemented with only ping and ping replies
     */
    // TODO: Move to protocol handler module
    void neighborDiscoveryHandler(pack* msg) {
        switch(msg->protocol) {
            case PROTOCOL_PING:
                dbg(NEIGHBOR_CHANNEL, "Neighbor discovery from %d. Adding to list & replying...\n", msg->src);
                call Neighbors.insert(msg->src, TIMEOUT_CYCLES);
                msg->src = AM_BROADCAST_ADDR; // Ping reply sets msg src as the reply's dest
                pingReply(msg);
                break;

            case PROTOCOL_PINGREPLY:
                dbg(NEIGHBOR_CHANNEL, "Neighbor reply from %d. Adding to neighbor list...\n", msg->src);
                call Neighbors.insert(msg->src, TIMEOUT_CYCLES);
                break;

            default:
                dbg(GENERAL_CHANNEL, "Unrecognized neighbor discovery protocol: %d\n", msg->protocol);
        }
    }

    /**
     * Called when a packet is recieved
     * Handles the validation of recieved packets, and identifies the type of packet
     */
    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){

        if (len == sizeof(pack)) {
            pack* myMsg=(pack*) payload;

            if (!call FloodingHandler.isValid(myMsg)) {
                return msg;
            }
            
            // Regular Ping
            if (myMsg->dest == TOS_NODE_ID) {
                pingHandler(myMsg);
                
            // Neighbor Discovery
            } else if (myMsg->dest == AM_BROADCAST_ADDR) {
                neighborDiscoveryHandler(myMsg);

            // Not Destination
            } else {
                call FloodingHandler.flood(myMsg);
            }
            return msg;
        }
        dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
        return msg;
    }

    /**
     * Sends a ping reply to the original packet's src node
     * The attached payload remains the same
     */
    // TODO: Move to protocol handler module with ping_handler()
    void pingReply(pack* msg) {
        makePack(&sendPackage, TOS_NODE_ID, msg->src, MAX_TTL, PROTOCOL_PINGREPLY, current_seq++, (uint8_t*)msg->payload, PACKET_MAX_PAYLOAD_SIZE);
        call FloodingHandler.flood(&sendPackage);
    }

    /**
     * Runs at a random amount of time, different for each node
     * Sends out a neighbor discovery packet (dest = AM_BROADCAST_ADDR, TTL = 1) to all connected nodes
     */
    // TODO: Move to neighbor discovery handler module
    event void NeighborTimer.fired() {
        // Using dest=AM_BROADCAST_ADDR for the ID of a neighbor discovery packet
        // Having 65535 nodes in a network is less likely than a node with ID 0 being part of the network
        uint8_t* payload = "Neighbor Discovery\n";
        decrement_timeout();
        makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 1, PROTOCOL_PING, current_seq++, payload, PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(sendPackage, AM_BROADCAST_ADDR);
    }

    /**
     * Called when simulation issues a ping command to the node
     */
    event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
        dbg(GENERAL_CHANNEL, "PING EVENT \n");
        makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, PROTOCOL_PING, current_seq++, payload, PACKET_MAX_PAYLOAD_SIZE);
        call FloodingHandler.flood(&sendPackage);
    }

    /**
     * Called when simulation issues a command to print the list of neighbor node IDs
     */
    event void CommandHandler.printNeighbors(){
        uint16_t i;
        uint32_t* nodes = call Neighbors.getKeys();

        dbg(GENERAL_CHANNEL, "--- Neighbors of Node %d ---\n", TOS_NODE_ID);
        for (i = 0; i < call Neighbors.size(); i++) {
            dbg(GENERAL_CHANNEL, "%d\n", nodes[i]);
        }
        dbg(GENERAL_CHANNEL, "---------------------------\n");
    }

    event void CommandHandler.printRouteTable(){ dbg(GENERAL_CHANNEL, "printRouteTable\n"); }

    event void CommandHandler.printLinkState(){ dbg(GENERAL_CHANNEL, "printLinkState\n"); }

    event void CommandHandler.printDistanceVector(){ dbg(GENERAL_CHANNEL, "printDistanceVector\n"); }

    event void CommandHandler.setTestServer(){ dbg(GENERAL_CHANNEL, "setTestServer\n"); }

    event void CommandHandler.setTestClient(){ dbg(GENERAL_CHANNEL, "setTestClient\n"); }

    event void CommandHandler.setAppServer(){ dbg(GENERAL_CHANNEL, "setAppServer\n"); }

    event void CommandHandler.setAppClient(){ dbg(GENERAL_CHANNEL, "setAppClient\n"); }

    /**
     * Assembles a packet given by the first parameter using the other parameters
     */
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }

    /**
     * Removes 1 'cycle' from all the timeout values on the neighbor list
     * Removes the node ID from the list if the timeout drops to 0
     */
    // TODO: Move to neighbor discovery module
    void decrement_timeout() {
        uint16_t i;
        uint32_t* nodes = call Neighbors.getKeys();

        // Subtract 1 'clock cycle' from all the timeout values
        for (i = 0; i < call Neighbors.size(); i++) {
            uint16_t timeout = call Neighbors.get(nodes[i]);
            call Neighbors.insert(nodes[i], timeout - 1);

            // Node stopped replying, drop it
            if (timeout - 1 <= 0) {
                call Neighbors.remove(nodes[i]);
            }
        }
    }

    /**
     * Generates a random 16-bit number between 'min' and 'max'
     */
    uint16_t randNum(uint16_t min, uint16_t max) {
        return ( call Random.rand16() % (max-min+1) ) + min;
    }
}
