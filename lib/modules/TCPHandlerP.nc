#include <Timer.h>
#include "../../includes/socket.h"
#include "../../includes/packet.h"

module TCPHandlerP {
    provides interface TCPHandler;

    uses interface Timer<TMilli> as SrcTimeout;
    uses interface Hashmap<socket_t> as SocketMap;
}

implementation {
    event void TCPHandler.fired() {
    
    }

    command void TCPHandler.start() {
        if (!call SrcTimeout.isRunning()) {
            call SrcTimeout.startPeriodic(3000);
        }
    }
    
    command void TCPHandler.send(pack* msg) {
        // create socket if it doesnt already exist
        // update state to SYN_SENT
        // send SYN packet to dest node
        socket_t srcSock;
        srcSock = msg -> src;
    }

    command void TCPHandler.recieve(pack* msg) {
        // create socket if it doesnt aready exist
        // 
        socket_t destSock;
        destSock = msg -> dest; 
        
    }
}
