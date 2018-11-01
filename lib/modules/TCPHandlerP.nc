#include <Timer.h>
#include "../../includes/socket.h"
#include "../../includes/packet.h"
#include "../../includes/tcp_header.h"
module TCPHandlerP {
    provides interface TCPHandler;

    uses interface Timer<TMilli> as SrcTimeout;
    uses interface Hashmap<socket_store_t> as SocketMap;
}

implementation {
    event void SrcTimeout.fired(){
        
    }

    command void TCPHandler.start() {
        if (!call SrcTimeout.isRunning()) {
            call SrcTimeout.startPeriodic(3000);
        }
    }
    
    command void TCPHandler.send(uint8_t dest, uint8_t srcPort, uint8_t destPort, uint32_t transfer) {
        // create socket if it doesnt already exist
        // update state to SYN_SENT
        // send SYN packet to dest node
        
        socket_store_t srcSock;
        srcSock.src = srcPort;
        if (srcSock.state == CLOSED){
            tcp_header syn_header; 
            pack msg;

            srcSock.state = SYN_SENT;
            syn_header.src_port = srcPort;
            syn_header.dest_port = destPort;
            syn_header.flags = SYN;
            syn_header.seq = 0;
            syn_header.advert_window = 1;
            msg.src = TOS_NODE_ID;
            msg.dest = dest;
            msg.seq = 0;
            msg.TTL = MAX_TTL;
            msg.protocol = PROTOCOL_TCP;
            memcpy(&msg.payload,&syn_header,TCP_PAYLOAD_SIZE);  


        }

       
        
    


    }

    command void TCPHandler.recieve(pack* msg) {
        // create socket if it doesnt aready exist
        // 

        socket_store_t destSock;
        destSock.src = msg -> dest; 
        if (destSock.state == LISTEN){
            destSock.state = SYN_RCVD;
        }
        
    }
}
