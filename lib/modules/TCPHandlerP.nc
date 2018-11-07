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

    /* Prototypes */
    void sendSyn(uint8_t dest, uint8_t srcPort, uint8_t destPort);
    void sendAck(pack* original_message);
    void sendFin(uint16_t dest, uint8_t srcPort, uint8_t destPort);

    socket_t getNextFD();
    socket_t getFD(uint16_t dest, uint16_t srcPort, uint16_t destPort);
    void addSocket(socket_store_t socket);
    void updateState(socket_t socketFD, enum socket_state new_state);

    void send(socket_t socketFD, uint32_t transfer);

    /**
     * Gets the next valid file descriptor for a socket.
     * Called when adding a new socket to the map of sockets.
     *
     * @return the next valid file descriptor, or 0 if no valid file descriptors
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
     * Gets the file descriptor of a socket.
     *
     * @param dest the node ID for packet destinations from the socket.
     * @param srcPort the local port associated with the socket.
     * @param destPort the remote port for packet destinations from the socket.
     *
     * @return the file descriptor associated with the socket, or 0
     *         if one does not exist.
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
     * Adds a socket to the map of sockets.
     * Automatically assigns a file descriptor to the socket.
     *
     * @param socket the socket to add to the list.
     */
    void addSocket(socket_store_t socket) {
        call SocketMap.insert(next_fd, socket);
        next_fd = getNextFD();
    }

    /**
     * Updates a socket's state based on its file descriptor.
     *
     * @param socketFD the file descriptor associated with the socket.
     * @param new_state the state to update the socket to.
     */
    void updateState(socket_t socketFD, enum socket_state new_state) {
        socket_store_t socket;

        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "Error: invalid file descriptor passed to update.\n");
            return;
        }

        socket = call SocketMap.get(socketFD);
        socket.state = new_state;
        call SocketMap.insert(socketFD, socket);
    }

    /**
     * Starts a 'server' TCP connection, waiting to recieve packets from the client.
     *
     * @param port the port to listen for connections on.
     */
    command void TCPHandler.startServer(uint16_t port) {
        uint16_t num_connections = call SocketMap.size();
        socket_store_t socket;

        if (num_connections == MAX_NUM_OF_SOCKETS) {
            dbg(TRANSPORT_CHANNEL, "Cannot create server at Port %d: Max num of sockets reached\n");
        }

        socket.src = TOS_NODE_ID;
        socket.state = LISTEN;

        // TODO: Fill in the rest of the server socket stuff

        addSocket(socket);
        dbg(TRANSPORT_CHANNEL, "Server started on Port %d\n", port);
        // TODO: Figure out what the pdf means starting with the 'startTimer' line
    }

    /**
     * Starts a 'client' TCP connection, requires a server to be listening first.
     *
     * @param dest the node ID of the server.
     * @param srcPort the client port to send the packets from.
     * @param destPort the server port to send the packets to.
     * @param transfer the number of bytes to transfer w/ value: (0..transfer-1).
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

        // TODO: Fill in the rest of the client socket stuff

        addSocket(socket);

        dbg(TRANSPORT_CHANNEL, "Client started on Port %d with destination %d: %d\n", srcPort, dest, destPort);
        dbg(TRANSPORT_CHANNEL, "Transferring %d bytes to destination...\n", transfer);

        send(getFD(dest, srcPort, destPort), transfer);
    }

    /**
     * Closes the 'client' TCP connection associated with the parameters.
     * 
     * @param dest the node ID of the server of this connection.
     * @param srcPort the local port number associated with the connection.
     * @param destPort the server's port associated with the connection.
     */
    command void TCPHandler.closeClient(uint16_t dest, uint16_t srcPort, uint16_t destPort) {
        socket_t fd = getFD(dest, srcPort, destPort);
        dbg(TRANSPORT_CHANNEL, "Closing client on Port %d with destination %d: %d\n", srcPort, dest, destPort);
        
        if (fd == 0) {
            dbg(TRANSPORT_CHANNEL, "Error: Cannot close client, socket not found\n");
        }

        sendFin(dest, srcPort, destPort);
        updateState(fd, CLOSED);
        // Wait for the ack before removing
        // call SocketMap.remove(fd);
    }

    /**
     * Starts a TCP connection through a socket and sends a series of bytes to the server.
     * 
     * @param socketFD the file descriptor for this connection's socket.
     * @param transfer the number of bytes to send to the server w/ value: (0..transfer-1).
     */
    void send(socket_t socketFD, uint32_t transfer) {
        socket_store_t socket;
        
        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "Error: Invalid socketFD in send.\n");
        }

        socket = call SocketMap.get(socketFD);

        if (socket.state != CLOSED) {
            dbg(TRANSPORT_CHANNEL, "Error: Send command recieved for an active socket: From %d to %d:%d\n", socket.src, 
                                                                                                            socket.dest.addr,
                                                                                                            socket.dest.port);
        }

        updateState(socketFD, SYN_SENT);
        sendSyn(socket.dest.addr, socket.src, socket.dest.port);
    }

    event void SrcTimeout.fired(){
        
    }

    command void TCPHandler.start() {
        if (!call SrcTimeout.isRunning()) {
            call SrcTimeout.startPeriodic(3000);
        }
    }

    /**
     * Processes TCP packet recieved by this node and update socket state.
     * Performs actions based on the socket's state and the packet's flag.
     * Called when the node recieves a TCP packet destined for it.
     *
     * @param msg the TCP packet to process
     */
    command void TCPHandler.recieve(pack* msg) {
        socket_t socketFD;
        socket_store_t socket;
        tcp_header header;
        
        // Retrieve TCP header from packet
        memcpy(&header, &(msg->payload), PACKET_MAX_PAYLOAD_SIZE);

        socketFD = getFD(msg->dest, header.src_port, header.dest_port); // REVIEW: Possible needs switched dest/src ports

        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "Error: No socket associated with message from Node %d\n", msg->src);
            return;
        }

        socket = call SocketMap.get(socketFD);

        switch(socket.state) {
            case CLOSED:
                // TODO: If FIN+ACK send final ACK, then delete socket from the map
                break;
            case LISTEN:
                // TODO: If SYN send SYN+ACK -> SYN_RCVD
                break;
            case ESTABLISHED:
                // TODO: If data/FIN -> send ack. If FIN -> CLOSED
                break;
            case SYN_SENT:
                // TODO: If SYN, send ACK back -> ESTABLISHED, then start sending the data
                break;
            case SYN_RCVD:
                // TODO: If ACK -> ESTABLISHED
                break;
            default:
                dbg(TRANSPORT_CHANNEL, "Error: Invalid socket state %d\n", socket.state);
        }
    }

    /**
     * Sends a syn packet to the destination.
     *
     * @param dest the node ID to send the packet to.
     * @param srcPort local port number associated with the sender.
     * @param destPort remote port number for the reciever.
     */
    void sendSyn(uint8_t dest, uint8_t srcPort, uint8_t destPort) {
        pack synPack;
        tcp_header syn_header;
                        
        syn_header.src_port = srcPort;
        syn_header.dest_port = destPort;
        syn_header.flags = SYN;
        syn_header.seq = 0; // TODO: Replace with socket stuff.
        syn_header.advert_window = 1; // FIXME: effectiveWindow of the socket                                                          
        synPack.src = TOS_NODE_ID;
        synPack.dest = dest;
        synPack.seq = 0; // FIXME: Fix the whole sequence number thing
        synPack.TTL = MAX_TTL;
        synPack.protocol = PROTOCOL_TCP;
        memcpy(&synPack.payload,&syn_header,TCP_PAYLOAD_SIZE);
        signal TCPHandler.route(&synPack);
    }

    /**
     * Sends an acknowledgement packet based on a recieved packet
     *
     * @param original_message the packet to be acknowledged
     */
    void sendAck(pack* original_message) {
        tcp_header originalHeader;
        pack ackPack;
        tcp_header ackHeader;

        // Retrieve the TCP header from the original message
        memcpy(&originalHeader, &(original_message->payload), PACKET_MAX_PAYLOAD_SIZE);
    
        ackPack.src = TOS_NODE_ID;
        ackPack.dest = original_message->src;
        ackPack.seq = 0; // FIXME: Fix the whole sequence number thing
        ackPack.TTL = MAX_TTL;
        ackPack.protocol = PROTOCOL_TCP;

        ackHeader.src_port = originalHeader.dest_port;
        ackHeader.dest_port = originalHeader.src_port;
        ackHeader.seq = originalHeader.seq; // TODO: Replace with socket stuff.
        ackHeader.ack = originalHeader.seq + 1; // TODO: Replace with socket stuff.
        ackHeader.advert_window = 1; // FIXME: effectiveWindow of the socket
        ackHeader.flags = ACK;
        ackHeader.payload_size = 0;

        // Insert the ackHeader into the packet
        memcpy(&ackPack.payload, &ackHeader, PACKET_MAX_PAYLOAD_SIZE);
        
        signal TCPHandler.route(&ackPack);
    }

    /**
     * Sends a fin packet to reciever 
     * @param dest is where the packet should end up 
     * @param srcPort is the port number of the source node
     * @param destPort is the port number of the destination node
     */
    void sendFin(uint16_t dest, uint8_t srcPort, uint8_t destPort) {
        pack fin_pack;
        tcp_header fin_header;

        fin_header.src_port = destPort;
        fin_header.dest_port = srcPort;
        fin_header.seq = 0; // TODO: Replace with... some stuff from socket.
        fin_header.advert_window = 1; // FIXME: effectiveWindow of the socket
        fin_header.flags = FIN;

        fin_pack.src = TOS_NODE_ID;
        fin_pack.dest = dest;
        fin_pack.seq = 0; // FIXME: Fix the whole sequence number thing
        fin_pack.TTL = MAX_TTL;
        fin_pack.protocol = PROTOCOL_TCP;

        memcpy(&fin_pack.payload, &fin_header, PACKET_MAX_PAYLOAD_SIZE);
                                                                                                       
        signal TCPHandler.route(&fin_pack);                 
    }    
}

