#include "../../includes/socket.h"

configuration TCPHandlerC{
    provides interface TCPHandler;
}

implementation {
    components TCPHandlerP;
    TCPHandler = TCPHandlerP;
    
    components new HashmapC(socket_store_t, MAX_NUM_OF_SOCKETS);
    TCPHandlerP.SocketMap -> HashmapC;
}

