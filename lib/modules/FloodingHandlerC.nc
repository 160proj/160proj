/**
 * @author Jadon Hansell
 * 
 * Provides an implementation of a flooding method for packet transmission
 */

#include "../../includes/packet.h"

configuration FloodingHandlerC {
    provides interface FloodingHandler;
}

implementation {
    components FloodingHandlerP;
    FloodingHandler = FloodingHandlerP;

    components new SimpleSendC(AM_PACK);
    FloodingHandlerP.Sender -> SimpleSendC;

    components new ListC(pack, 128);
    FloodingHandlerP.PreviousPackets -> ListC;
}
