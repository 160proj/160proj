#include "../../includes/packet.h"

interface FloodingHandler {
    command bool isValid(pack* msg);
    command void flood(pack* msg);
}
