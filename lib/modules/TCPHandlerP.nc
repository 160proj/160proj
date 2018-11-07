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
    /* SECTION: Member Variables */

    socket_t next_fd = 1; /** Next open file descriptor to bind a socket to */

    /* SECTION: Prototypes */

    void sendSyn(socket_t socketFD);
    void sendAck(socket_t socketFD, pack* original_message);
    void sendFin(socket_t socketFD);

    void send(socket_t socketFD, uint32_t transfer);
    void write(socket_t socketFD, pack* msg);

    socket_t getNextFD();
    socket_t getFD(uint16_t dest, uint16_t srcPort, uint16_t destPort);
    void addSocket(socket_store_t socket);
    void updateState(socket_t socketFD, enum socket_state new_state);
    void updateSocket(socket_t socketFD, socket_store_t new_socket);

    /* SECTION: Private Functions */

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
     * Updates the stored socket.
     *
     * @param socketFD the file descriptor for the socket to update.
     * @param socket a socket containing the updated values.
     */
    void updateSocket(socket_t socketFD, socket_store_t new_socket) {
        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "Error: invalid socket file descriptor for socket update\n");
            return;
        }
        call SocketMap.insert(socketFD, new_socket);
    }

    /**
     * Writes a packet to the send buffer.
     * Drops the packet if the send buffer is full.
     *
     * @param socketFD the file descriptor for the socket.
     * @param msg the packet to write.
     */
    void write(socket_t socketFD, pack* msg) {
        // FIXME make it not instantly send at all times
        // put the packet in the send buffer and send from that in order
        socket_store_t socket;

        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "Error: Invalid socket file descriptor when writing\n");
            return;
        }

        socket = call SocketMap.get(socketFD);

        socket.lastWritten++;
        signal TCPHandler.route(msg);
        socket.lastSent++;

        updateSocket(socketFD, socket);
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
        sendSyn(socketFD);
    }

    /* SECTION: Commands */

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
        socket.lastWritten = 0;
        socket.lastAck = 0;
        socket.lastSent = 0;

        // TODO: Fill in the rest of the client socket stuff

        addSocket(socket);

        dbg(TRANSPORT_CHANNEL, "Client started on Port %d with destination %d: %d\n", srcPort, dest, destPort);
        dbg(TRANSPORT_CHANNEL, "Transferring %d bytes to destination...\n", transfer);

        send(getFD(dest, srcPort, destPort), transfer);
        // TODO: Actually send the bytes
    }

    /**
     * Closes the 'client' TCP connection associated with the parameters.
     * 
     * @param dest the node ID of the server of this connection.
     * @param srcPort the local port number associated with the connection.
     * @param destPort the server's port associated with the connection.
     */
    command void TCPHandler.closeClient(uint16_t dest, uint16_t srcPort, uint16_t destPort) {
        socket_t socketFD = getFD(dest, srcPort, destPort);
        dbg(TRANSPORT_CHANNEL, "Closing client on Port %d with destination %d: %d\n", srcPort, dest, destPort);
        
        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "Error: Cannot close client, socket not found\n");
        }

        sendFin(socketFD);
        updateState(socketFD, CLOSED);
        // Wait for the ack before removing
        // call SocketMap.remove(fd);
    }

    /**
     * Processes TCP packet recieved by this node and update socket state.
     * Performs actions based on the socket's state and the packet's flag.
     * Called when the node recieves a TCP packet destined for it.
     *
     * @param msg the TCP packet to process
     */
    command void TCPHandler.recieve(pack* msg) {
        // FIXME: Instantly add msg into recieve buffer, more messages may be waiting
        socket_t socketFD;
        socket_store_t socket;
        tcp_header header;
        
        // Retrieve TCP header from packet
        memcpy(&header, &(msg->payload), PACKET_MAX_PAYLOAD_SIZE);

        // REVIEW: Possibly needs switched dest/src ports
        socketFD = getFD(msg->dest, header.src_port, header.dest_port);

        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "Error: No socket associated with message from Node %d\n", msg->src);
            return;
        }

        socket = call SocketMap.get(socketFD);

        // TODO: Give this its own function?
        switch(socket.state) {
            case CLOSED:
                // TODO: If FIN+ACK send final ACK, then delete socket from the map
                break;
            case LISTEN:
                // TODO: If SYN send SYN+ACK -> SYN_RCVD; set socket dest
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

    /* SECTION: Events */

    // TODO: Remove or refactor
    event void SrcTimeout.fired(){
        
    }

    /*
     * SECTION: Temp 
     * TODO: Move to function section
     */


    /**
     * Sends a syn packet to the destination.
     *
     * @param socketFD the file descriptor for the socket
     */
    void sendSyn(socket_t socketFD) {
        socket_store_t socket;
        pack synPack;
        tcp_header syn_header;
                        
        if (!socketFD) {
            dbg (TRANSPORT_CHANNEL, "Invalid socket file descriptor in sendSyn\n");
            return;
        }

        socket = call SocketMap.get(socketFD);

        synPack.src = TOS_NODE_ID;
        synPack.dest = socket.dest.addr;
        synPack.seq = 0; // FIXME: Fix the whole sequence number thing
        synPack.TTL = MAX_TTL;
        synPack.protocol = PROTOCOL_TCP;

        syn_header.src_port = socket.src;
        syn_header.dest_port = socket.dest.port;
        syn_header.flags = SYN;
        syn_header.seq = socket.lastWritten + 1;
        syn_header.advert_window = socket.effectiveWindow;

        memcpy(&synPack.payload,&syn_header,TCP_PAYLOAD_SIZE);

        write(socketFD, &synPack);
    }

    /**
     * Sends an acknowledgement packet based on a recieved packet.
     *
     * @param socketFD the file descriptor for the socket.
     * @param original_message the packet to be acknowledged.
     */
    void sendAck(socket_t socketFD, pack* original_message) {
        socket_store_t socket;
        tcp_header originalHeader;
        pack ackPack;
        tcp_header ackHeader;

        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "Error: Invalid socket file descriptor in sendAck\n");
            return;
        }

        socket = call SocketMap.get(socketFD);

        // Retrieve the TCP header from the original message
        memcpy(&originalHeader, &(original_message->payload), PACKET_MAX_PAYLOAD_SIZE);

        ackPack.src = TOS_NODE_ID;
        ackPack.dest = socket.dest.addr;
        ackPack.seq = 0; // FIXME: Fix the whole sequence number thing
        ackPack.TTL = MAX_TTL;
        ackPack.protocol = PROTOCOL_TCP;

        ackHeader.src_port = originalHeader.dest_port;
        ackHeader.dest_port = originalHeader.src_port;
        ackHeader.seq = socket.lastWritten + 1; // REVIEW: Maybe not the correct value
        ackHeader.ack = socket.nextExpected;    // REVIEW: Maybe not the correct value
        ackHeader.advert_window = socket.effectiveWindow;
        ackHeader.flags = ACK;

        // Insert the ackHeader into the packet
        memcpy(&ackPack.payload, &ackHeader, PACKET_MAX_PAYLOAD_SIZE);
        
        signal TCPHandler.route(&ackPack);
    }            

    /**
     * Sends a fin packet to reciever
     *
     * @param socketFD the file descriptor for the socket.
     */
    void sendFin(socket_t socketFD) {
        socket_store_t socket; 
        pack finPack;
        tcp_header fin_header;

        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "Error: Invalid socket file descriptor in sendFin\n");
            return;
        }

        socket = call SocketMap.get(socketFD);

        finPack.src = TOS_NODE_ID;
        finPack.dest = socket.dest.addr;
        finPack.seq = 0; // FIXME: Fix the whole sequence number thing
        finPack.TTL = MAX_TTL;
        finPack.protocol = PROTOCOL_TCP;

        fin_header.src_port = socket.dest.port;
        fin_header.dest_port = socket.src;
        fin_header.seq = socket.lastWritten+1;
        fin_header.advert_window = socket.effectiveWindow;
        fin_header.flags = FIN;

        memcpy(&finPack.payload, &fin_header, PACKET_MAX_PAYLOAD_SIZE);
                                                                                                       
        write(socketFD, &finPack);                
    }    
}

