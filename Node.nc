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
    
    uses interface Hashmap<uint16_t> as PreviousPackets;
    uses interface Hashmap<uint16_t> as Neighbors;

    uses interface FloodingHandler;
}

implementation{
    const uint16_t TIMEOUT_CYCLES = 10; // # of timer runs before timeout
    pack sendPackage;
    uint16_t current_seq = 0;

    // Prototypes
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
    void pingReply(pack* msg);
    bool isDuplicate(uint16_t node_id, uint16_t sequence_num);
    void decrement_timeout();
    void pingHandler(pack* msg);
    void neighborDiscoveryHandler(pack* msg);

    event void Boot.booted(){
        call AMControl.start();

        dbg(GENERAL_CHANNEL, "Booted\n");
        call NeighborTimer.startPeriodic(call Random.rand16());
    }

    event void AMControl.startDone(error_t err){
        if (err == SUCCESS) {
            dbg(GENERAL_CHANNEL, "Radio On\n");
        } else {
            //Retry until successful
            call AMControl.start();
        }
    }

    event void AMControl.stopDone(error_t err){}

    void pingHandler(pack* msg) {
        switch(msg->protocol) {
            case PROTOCOL_PING:
                dbg(GENERAL_CHANNEL, "Ping recieved from %d. Sending reply...\n", msg->src);
                dbg(GENERAL_CHANNEL, "Packet Payload: %s\n", msg->payload);
                pingReply(msg);
                break;
                    
            case PROTOCOL_PINGREPLY:
                dbg(GENERAL_CHANNEL, "Ping reply recieved from %d.\n", msg->src);
                break;
                    
            default:
                dbg(GENERAL_CHANNEL, "Unrecognized ping protocol: %d\n", msg->protocol);
        }
    }

    void neighborDiscoveryHandler(pack* msg) {
        switch(msg->protocol) {
            case PROTOCOL_PING:
                dbg(NEIGHBOR_CHANNEL, "Neighbor discovery from %d. Adding to list & replying...\n", msg->src);
                call Neighbors.insert(msg->src, TIMEOUT_CYCLES);
                msg->src = AM_BROADCAST_ADDR; // Invert src/dest for ping reply
                msg->dest = TOS_NODE_ID;      // TODO re-implement with flooding module
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

    void pingReply(pack* msg) {
        makePack(&sendPackage, TOS_NODE_ID, msg->src, MAX_TTL, PROTOCOL_PINGREPLY, current_seq++, (uint8_t*)msg->payload, PACKET_MAX_PAYLOAD_SIZE);
        call FloodingHandler.flood(&sendPackage);
    }

    void decrement_timeout() {
        uint16_t i;
        uint32_t* nodes = call Neighbors.getKeys();

        for (i = 0; i < call Neighbors.size(); i++) {
            uint16_t timeout = call Neighbors.get(nodes[i]);
            call Neighbors.insert(nodes[i], timeout - 1);
            if (timeout - 1 <= 0) {
                call Neighbors.remove(nodes[i]);
            }
        }
    }

    event void NeighborTimer.fired() {
        uint8_t* payload = "Neighbor Discovery\n";
        decrement_timeout();
        makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 1, PROTOCOL_PING, current_seq++, payload, PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(sendPackage, AM_BROADCAST_ADDR);
    }

    event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
        dbg(GENERAL_CHANNEL, "PING EVENT \n");
        makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, PROTOCOL_PING, current_seq++, payload, PACKET_MAX_PAYLOAD_SIZE);
        call FloodingHandler.flood(&sendPackage);
    }

    event void CommandHandler.printNeighbors(){
        uint16_t i;
        uint32_t* nodes = call Neighbors.getKeys();

        dbg(NEIGHBOR_CHANNEL, "--- Neighbors of Node %d ---\n", TOS_NODE_ID);
        for (i = 0; i < call Neighbors.size(); i++) {
            dbg(NEIGHBOR_CHANNEL, "%d\n", nodes[i]);
        }
        dbg(NEIGHBOR_CHANNEL, "---------------------------\n");
    }

    event void CommandHandler.printRouteTable(){ dbg(GENERAL_CHANNEL, "printRouteTable\n"); }

    event void CommandHandler.printLinkState(){ dbg(GENERAL_CHANNEL, "printLinkState\n"); }

    event void CommandHandler.printDistanceVector(){ dbg(GENERAL_CHANNEL, "printDistanceVector\n"); }

    event void CommandHandler.setTestServer(){ dbg(GENERAL_CHANNEL, "setTestServer\n"); }

    event void CommandHandler.setTestClient(){ dbg(GENERAL_CHANNEL, "setTestClient\n"); }

    event void CommandHandler.setAppServer(){ dbg(GENERAL_CHANNEL, "setAppServer\n"); }

    event void CommandHandler.setAppClient(){ dbg(GENERAL_CHANNEL, "setAppClient\n"); }

    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }
}
