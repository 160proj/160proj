/**
 * @author Jadon Hansell
 * 
 * Distance vector implementtion for routing packets
 */

#include "../../includes/route.h"

configuration RoutingHandlerC {
    provides interface RoutingHandler;
}

implementation {
    components RoutingHandlerP;
    RoutingHandler = RoutingHandlerP;

    // No more than 256 nodes in system
    components new HashmapC(Route, 256);
    RoutingHandlerP.RoutingTable -> HashmapC;

    components new SimpleSendC(AM_PACK);
    RoutingHandlerP.Sender -> SimpleSendC;
}