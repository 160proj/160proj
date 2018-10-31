#include "../../includes/packet.h"

interface TCPHandler {
    command void start();
    command void send(pack* msg);
    command void recieve(pack* msg);
}
