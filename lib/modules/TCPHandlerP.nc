#include <Timer.h>
#include "../../includes/socket.h"
#include "../../includes/packet.h"
#include "../../includes/tcp_header.h"
module TCPHandlerP {
    provides interface TCPHandler;

    uses interface Timer<TMilli> as SrcTimeout;
}

implementation {
event void TCPHandler.fired(){
    
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
        
        socket_store_t srcSock;
        srcSock -> src = msg -> src;
        if (srcSock -> state == socket_state.CLOSED){
            srcSock -> state = socket_state.SYN_SENT;
            return;
        }
        
    


    }

    command void TCPHandler.recieve(pack* msg) {
        // create socket if it doesnt aready exist
        // 

        socket_t destSock;
        destSock = msg -> dest; 
        
    }
}
