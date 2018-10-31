configuration TCPHandlerC{
    provides interface TCPHandler;
}

implementation {
    components TCPHandlerP;
    TCPHandler = TCPHandlerP;
    
}

