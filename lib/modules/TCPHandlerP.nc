module TCPHandlerP {
    provides interface TCPHandler;

    uses interface Timer<TMilli> as SrcTimeout;
}

implementation {

    event void SrcTimeout.fired(){
        

    }
    command void TCPHandler.start() {
        if (!call SrcTimeout.isRunning()) {
            call SrcTimeout.startPeriodic(1000);
        }
    }
    
}
