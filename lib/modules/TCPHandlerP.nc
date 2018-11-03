#include <Timer.h>
#include "../../includes/socket.h"
#include "../../includes/packet.h"
#include "../../includes/tcp_header.h"
module TCPHandlerP {
    provides interface TCPHandler;

    uses interface Timer<TMilli> as SrcTimeout;
    uses interface Hashmap<socket_store_t> as SocketMap;
}

implementation {
    socket_t next_fd = 1; /** Next open file descriptor to bind a socket to */

    /**
     * Returns the next valid file descriptor
     * Returns 0 if none were found
     */
    socket_t getNextFD() {
        uint32_t* fds = call SocketMap.getKeys(); 
        uint16_t size = call SocketMap.size();
        socket_t fd = 1;
        uint8_t i;

        for (fd = 1; fd > 0; fd++) {
            bool found = FALSE;
            for (i = 0; i < size; i++) {
                if (fd != (socket_t)fds[i]) {
                    found = TRUE;
                }
            }

            if (!found) {
                return fd;
            }      
        }

        dbg(TRANSPORT_CHANNEL, "Error: No valid next file descriptor found\n");
        return 0;
    }

    /**
     * Returns the file descriptor associated with the socket for dest, srcPort, and destPort
     * Returns 0 if no sockets are found with those criteria
     */
    socket_t getFD(uint16_t dest, uint16_t srcPort, uint16_t destPort) {
        uint32_t* fds = call SocketMap.getKeys();
        uint16_t size = call SocketMap.size();
        uint16_t i;

        for (i = 0; i < size; i++) {
            socket_store_t socket = call SocketMap.get(fds[i]);
            if (socket.src == srcPort &&
                socket.dest.port == destPort &&
                socket.dest.addr == dest) {
                    return (socket_t)fds[i];
                }
        }

        dbg(TRANSPORT_CHANNEL, "Error: File descriptor not found for dest: %d, srcPort: %d, destPort: %d", dest, srcPort, destPort);
        return 0;
    }

    /**
     * Adds a socket to the list of sockets
     * AUtomatically assigns a file descriptor
     */
    void addSocket(socket_store_t socket) {
        call SocketMap.insert(next_fd, socket);
        next_fd = getNextFD();
    }

    /**
     * Create a 'server' socket on 'port' and begins listening for incoming connections
     */
    command void TCPHandler.startServer(uint16_t port) {
        uint16_t num_connections = call SocketMap.size();
        socket_store_t socket;

        if (num_connections == MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "Cannot create server at Port %d: Max num of sockets reached\n");
        }

        socket.src = TOS_NODE_ID;
        socket.state = LISTEN;

        addSocket(socket);
        dbg(TRANSPORT_CHANNEL, "Server started on Port %d\n", port);
        // TODO: Figure out what the pdf means starting with the 'startTimer' line
    }

    /**
     * Creates a 'client' socket on srcPort, and attempts to send 'transfer' bytes to
     * port 'destPort' at node 'dest'
     */
    command void TCPHandler.startClient(uint16_t dest, uint16_t srcPort,
                                        uint16_t destPort, uint16_t transfer) {
        socket_store_t socket;
        socket_addr_t destination;
        socket.src = TOS_NODE_ID;

        destination.port = destPort;
        destination.addr = dest;
        socket.dest = destination;

        socket.state = CLOSED;

        addSocket(socket);

        dbg(TRANSPORT_CHANNEL, "Client started on Port %d with destination %d: %d\n", srcPort, dest, destPort);
        dbg(TRANSPORT_CHANNEL, "Transferring %d bytes to destination...\n", transfer);

        //TODO: Send bytes
    }

    /**
     * Closes the connection on 'srcPort' associated with port 'destPort' at node 'dest'
     */
    command void TCPHandler.closeClient(uint16_t dest, uint16_t srcPort, uint16_t destPort) {
        socket_t fd = getFD(dest, srcPort, destPort);
        dbg(TRANSPORT_CHANNEL, "Closing client on Port %d with destination %d: %d\n", srcPort, dest, destPort);
        
        if (fd == 0) {
            dbg(TRANSPORT_CHANNEL, "Error: Cannot close client, socket not found\n");
        }

        call SocketMap.remove(fd);
    }

    event void SrcTimeout.fired(){
        
    }

    command void TCPHandler.start() {
        if (!call SrcTimeout.isRunning()) {
            call SrcTimeout.startPeriodic(3000);
        }
    }
    
    command void TCPHandler.send(uint8_t dest, uint8_t srcPort, uint8_t destPort, uint32_t transfer) {
        // create socket if it doesnt already exist
        // update state to SYN_SENT
        // send SYN packet to dest node
        
        socket_store_t srcSock;
        srcSock.src = srcPort;
        if (srcSock.state == CLOSED){
            tcp_header syn_header; 
            pack msg;

            srcSock.state = SYN_SENT;
            syn_header.src_port = srcPort;
            syn_header.dest_port = destPort;
            syn_header.flags = SYN;
            syn_header.seq = 0;
            syn_header.advert_window = 1;
            msg.src = TOS_NODE_ID;
            msg.dest = dest;
            msg.seq = 0;
            msg.TTL = MAX_TTL;
            msg.protocol = PROTOCOL_TCP;
            memcpy(&msg.payload,&syn_header,TCP_PAYLOAD_SIZE);  


        }

       
        
    


    }

    command void TCPHandler.recieve(pack* msg, uint8_t dest, uint8_t srcPort, uint8_t destPort, uint32_t transfer) {
        // create socket if it doesnt aready exist
        // 

        socket_store_t destSock;
        destSock.src = msg -> dest; 
        if (destSock.state == LISTEN){
            tcp_header syn_header; 
            

            destSock.state = SYN_RCVD;
            syn_header.src_port = srcPort;
            syn_header.dest_port = destPort;
            syn_header.flags = SYN;
            syn_header.seq = 0;
            syn_header.ack = 1;
            syn_header.advert_window = 1;
            msg->dest = msg->src;
            msg->src = TOS_NODE_ID;
            msg->seq = 0;
            msg->TTL = MAX_TTL;
            msg->protocol = PROTOCOL_TCP;
            memcpy(msg->payload,&syn_header,TCP_PAYLOAD_SIZE);  
            
        }
        
    }
}
