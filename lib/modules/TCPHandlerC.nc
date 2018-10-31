#include "../../socket.h"

configuration TCPHandlerC{
    provides interface TCPHandler;
}

implementation {
    components TCPHandlerP;
    TCPHandler = TCPHandlerP;
    
    components new HashmapC(socket_t, 256);
    TCPHandler.SocketMap -> HashmapC;
}

