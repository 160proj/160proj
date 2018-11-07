#ifndef TCP_HEADER_H
#define TCP_HEADER_H

enum {
    TCP_HEADER_SIZE = 10,
    TCP_PAYLOAD_SIZE = 20 - TCP_HEADER_SIZE,
};

enum flags {
    SYN,
    ACK,
    FIN,
    DATA,
};

typedef nx_struct tcp_header {
    nx_uint8_t src_port;
    nx_uint8_t dest_port;
    nx_uint16_t seq;
    nx_uint16_t ack;
    nx_uint16_t advert_window;
    nx_uint8_t flag;
    nx_uint8_t payload_size; // in bytes
    nx_uint8_t payload[TCP_PAYLOAD_SIZE];
} tcp_header;

#endif // TCP_HEADER_H
