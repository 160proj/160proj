#ifndef ROUTE_H
#define ROUTE_H

enum {
    MAX_ROUTE_TTL = 20,
    ROUTE_SIZE = 4
};

typedef nx_struct Route {
    nx_uint8_t dest;
    nx_uint8_t next_hop;
    nx_uint8_t cost;
    nx_uint8_t TTL;
} Route;

#endif // ROUTE_H