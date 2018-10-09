/**
 * @author Jadon Hansell
 * 
 * Flooding method for packet transmission
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

    components new ListC(pack, 64);
    FloodingHandlerP.PreviousPackets -> ListC;
}
