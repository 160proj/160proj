#include "../../includes/packet.h"


module FloodingHandlerP {
    provides interface FloodingHandler;

    uses interface SimpleSend as Sender;
    uses interface List<pack> as PreviousPackets;
}

implementation {
    bool isDuplicate(uint16_t src, uint16_t seq) {
        uint16_t i;
        // Loop over previous packets
        for (i = 0; i < call PreviousPackets.size(); i++) {
            pack prevPack = call PreviousPackets.get(i);

            // Packet can be identified by src && seq number
            if (prevPack.src == src && prevPack.seq == seq) {
                return TRUE;
            }
        }
        return FALSE;
    }

    command bool FloodingHandler.isValid(pack* msg) {
        if (msg->TTL <= 0) {
            dbg(FLOODING_CHANNEL, "TTL of packet reached. Dropping...\n");
            return FALSE;
        }

        if (isDuplicate(msg->src, msg->seq)) {
            dbg(FLOODING_CHANNEL, "Duplicate packet. Dropping...\n");
            return FALSE;
        }

        return TRUE;
    }

    void sendFlood(pack* msg) {
        // AM_BROADCAST_ADDR used for neighbor discovery, not necessary to print
        if (msg->dest != AM_BROADCAST_ADDR) {
            dbg(FLOODING_CHANNEL, "Packet recieved from %d. Destination: %d. Flooding...\n", msg->src, msg->dest);
        }
        msg->TTL--;
        call Sender.send(*msg, AM_BROADCAST_ADDR);
    }

    command void FloodingHandler.flood(pack* msg) {
        if (call FloodingHandler.isValid(msg)) {
            call PreviousPackets.pushbackdrop(*msg);
            sendFlood(msg);
        }
    }
}
