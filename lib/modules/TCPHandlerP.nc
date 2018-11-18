#include <stdlib.h>
#include <stdio.h>
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
    uint16_t* node_seq; /** Pointer to node's sequence number */

    /* SECTION: Prototypes */

    void sendSyn(socket_t socketFD);
    void sendAck(socket_t socketFD, pack* original_message);
    void sendFin(socket_t socketFD);

    void send(socket_t socketFD, uint32_t transfer);
    void write(socket_t socketFD, pack* msg);
    void connect(socket_t socketFD, uint16_t dest, socket_port_t destPort);

    socket_t getNextFD();
    socket_t getFD(uint16_t dest, uint16_t srcPort, uint16_t destPort);
    socket_t addSocket(socket_store_t socket);
    void updateState(socket_t socketFD, enum socket_state new_state);
    void updateSocket(socket_t socketFD, socket_store_t new_socket);
    void getState(enum socket_state state, char* str);

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

        dbg(TRANSPORT_CHANNEL, "[Error] getNextFD: No valid file descriptor found\n");
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
            socket_t socketFD = fds[i];
            socket_store_t socket = call SocketMap.get(socketFD);

            if (socket.src == srcPort &&
                socket.dest.port == destPort &&
                socket.dest.addr == dest) {
                    return socketFD;
            }
        }

        dbg(TRANSPORT_CHANNEL, "[Error] getFD: File descriptor not found for dest: %hu, srcPort: %hhu, destPort: %hhu\n", dest, srcPort, destPort);
        
        
        return 0;
    }

    /**
     * Get the name of the given socket state (for debugging)
     *
     * @param state the state of the socket
     * @param str the string to copy the name into
     */
    void getState(enum socket_state state, char* str) {
        switch(state) {
            case CLOSED:
                str = "CLOSED";
                break;
            case LISTEN:
                str = "LISTEN";
                break;
            case ESTABLISHED:
                str = "ESTABLISHED";
                break;
            case SYN_SENT:
                str = "SYN_SENT";
                break;
            case SYN_RCVD:
                str = "SYN_RCVD";
                break;
            default:
                sprintf(str, "%hhu", state);
        }
    }

    /**
     * Called when a server recieves a syn packet.
     * Creates a socket for the connection that's a copy of the server socket.
     *
     * @param dest the client's address.
     * @param srcPort the server's port.
     * @param destPort the client's port.
     *
     * @return the socket for the new connection, or NULL if unsuccessful
     */
    socket_t socketSyn(uint16_t dest, uint16_t srcPort, uint16_t destPort) {
        uint32_t* fds = call SocketMap.getKeys();
        uint16_t size = call SocketMap.size();
        uint16_t i;

        for (i = 0; i < size; i++) {
            socket_t socketFD = fds[i];
            socket_store_t socket = call SocketMap.get(socketFD);

            if (socket.src == srcPort &&
                socket.state == LISTEN &&
                socket.dest.addr == ROOT_SOCKET_ADDR &&
                socket.dest.port == ROOT_SOCKET_PORT) {
                    // Make copy of the server socket for the connection
                    socket_store_t new_socket = socket;
                    new_socket.state = SYN_RCVD;
                    new_socket.dest.addr = dest;
                    new_socket.dest.port = destPort;
                    return addSocket(new_socket);
            }
        }

        dbg(TRANSPORT_CHANNEL, "[Error] socketSyn: Cannot find server socket\n");
        return 0;
    }

    /**
     * Adds a socket to the map of sockets.
     * Automatically assigns a file descriptor to the socket.
     *
     * @param socket the socket to add to the list.
     *
     * @return the file descriptor for the new socket
     */
    socket_t addSocket(socket_store_t socket) {
        socket_t fd = next_fd;
        call SocketMap.insert(next_fd, socket);
        next_fd = getNextFD();
        return fd;
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
            dbg(TRANSPORT_CHANNEL, "[Error] updateState: Invalid file descriptor\n");
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
            dbg(TRANSPORT_CHANNEL, "[Error] updateSocket: Invalid socket descriptor\n");
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
            dbg(TRANSPORT_CHANNEL, "[Error] write: Invalid file descriptor\n");
            return;
        }
        
        socket = call SocketMap.get(socketFD);

        socket.lastWritten++;
        signal TCPHandler.route(msg);
        socket.lastSent++;
        //  TODO store the messages here (somehow do memcpy from the message and store it into the send Buffer)
        // memcpy(socket.sendBuff,&msg,128);                

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
            dbg(TRANSPORT_CHANNEL, "[Error] send: Invalid file descriptor\n");
            return;
        }

        socket = call SocketMap.get(socketFD);

        if (socket.state != CLOSED) {
            dbg(TRANSPORT_CHANNEL, "[Error] send: Command recieved for an active socket: From %hhu to %hu:%hhu\n", socket.src, 
                                                                                                                   socket.dest.addr,
                                                                                                                   socket.dest.port);
            return;
        }

        updateState(socketFD, SYN_SENT);
        sendSyn(socketFD);
    }

    /**
     * Fills the send buffer with the bytes to send
     */
    uint32_t fill(socket_t socketFD, uint32_t transfer) {
        socket_store_t socket;
        uint8_t start;
        uint8_t end;
        uint32_t i;
        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] fill: Invalid file descriptor\n");
            return (uint32_t)NULL;
        }

        socket = call SocketMap.get(socketFD);

        start = socket.lastSent + 1;
        end = socket.lastAck - 1;

        // Bound the start value
        if (start >= SOCKET_BUFFER_SIZE) {
            start = 0;
        }

        // Bound the end value
        if (end >= SOCKET_BUFFER_SIZE) {
            end = SOCKET_BUFFER_SIZE;
        }

        for (i = 0; i < transfer; i++) {
            uint8_t offset = start+i;

            // Make sure the offset wraps around
            if (start+i >= SOCKET_BUFFER_SIZE) {
                offset -= SOCKET_BUFFER_SIZE;
            }
            
            // Stop copying when buffer is full
            if (offset != end) {
                memcpy(socket.sendBuff + start + i,  &i, 1);
                socket.lastWritten = offset;
                updateSocket(socketFD, socket);
            } else {
                return i;
            }
        }
    }

    /**
     * Attempts to connect to the server
     *
     * @param serverFD the server to connect to
     * @param dest the address of the client
     * @param destPort the port of the client
     */
    void connect(socket_t serverFD, uint16_t dest, socket_port_t destPort) {
        socket_store_t socket;
        if (!serverFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] connect: Invalid server file descriptor\n");
            return;                                                    
        }

        socket = call SocketMap.get(serverFD);        
    }

    /**
     * Checks if an ACK packet has been acked already
     *
     * @param socketFD the file descriptor of the connection's socket
     * @param header the TCP header from the packet
     *
     * @return true if packet has been acked, false if the packet has not been acked
     */
    bool checkAck(socket_t socketFD, tcp_header header) {
        socket_store_t socket;

        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] checkAck: Invalid file descriptor\n");
            return FALSE;
        }

        socket = call SocketMap.get(socketFD);

        // Regular
        if (socket.lastSent > socket.lastAck) {
            return header.seq < socket.lastAck && header.seq > socket.lastSent;
        // Wraparound
        } else {
            return header.seq > socket.lastAck && header.seq < socket.lastSent;
        }
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
            dbg(TRANSPORT_CHANNEL, "Cannot create server at Port %hhu: Max num of sockets reached\n", port);
        }

        socket.src = port;
        socket.state = LISTEN;
        socket.dest.addr = ROOT_SOCKET_ADDR;
        socket.dest.port = ROOT_SOCKET_PORT;
        socket.effectiveWindow = 1;

        addSocket(socket);
        dbg(TRANSPORT_CHANNEL, "Server started on Port %hhu\n", port);
        // TODO: Figure out what the pdf means starting with the 'startTimer' line
        // fired() function that takes in 3 seconds and it 
    }

    /**
     * Starts a 'client' TCP connection, requires a server to be listening first.
     *
     * @param dest the node ID of the server.
     * @param srcPort the client port to send the packets from.
     * @param destPort the server port to send the packets to.
     * @param transfer the number of bytes to transfer w/ value: (0..transfer-1).
     * @param pointer to node's sequence number
     */
    command void TCPHandler.startClient(uint16_t dest, uint16_t srcPort,
                                        uint16_t destPort, uint16_t transfer) {
        socket_store_t socket;

        socket.src = srcPort;
        socket.dest.port = destPort;
        socket.dest.addr = dest;
        socket.state = CLOSED;
        socket.lastWritten = 0;
        socket.lastAck = 0;
        socket.lastSent = 0;
        socket.effectiveWindow = 1;

        // TODO: Fill in the rest of the client socket stuff

        addSocket(socket);

        dbg(TRANSPORT_CHANNEL, "Client started on Port %hhu with destination %hu: %hhu\n", srcPort, dest, destPort);
        dbg(TRANSPORT_CHANNEL, "Transferring %hu bytes to destination...\n", transfer);

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
        dbg(TRANSPORT_CHANNEL, "Closing client on Port %hhu with destination %hu: %hhu\n", srcPort, dest, destPort);
        
        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] closeClient: Invalid file descriptor\n");
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
        char dbg_string[20];
        // memcpy(socket.rcvdBuff, &msg, 128) FIXME: make the message go into buffer for recieving things 
        
        // Retrieve TCP header from packet
        memcpy(&header, &(msg->payload), PACKET_MAX_PAYLOAD_SIZE);

        if (header.flag == SYN) {
            socketSyn(msg->src, header.dest_port, header.src_port);
        }

        socketFD = getFD(msg->src, header.dest_port, header.src_port);

        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] recieve: No socket associated with message from Node %hu\n", msg->src);
            return;
        }

        socket = call SocketMap.get(socketFD);

        dbg(TRANSPORT_CHANNEL, "TCP Packet recieved:\n");
        logPack(msg);
        logHeader(&header);
        dbg(TRANSPORT_CHANNEL, "Socket:\n");
        logSocket(&socket);

        // TODO: Give this its own function?
        switch(socket.state) {
            case CLOSED:
                if (header.flag == FIN) {
                    sendAck(socketFD, msg);
                    call SocketMap.remove(socketFD);
                }      
                break;

            case LISTEN:
                if (header.flag == SYN){  
                    sendSyn(socketFD);
                    sendAck(socketFD, msg);
                    socketSyn(socketFD, msg->src, header.src_port);
                }
                break;

            case ESTABLISHED:
                if (header.flag == DAT) {
                    sendAck(socketFD, msg);
                    // TODO: Process data
                }
                if (header.flag == ACK) {
                    // TODO: Update ack values
                }
                if (header.flag == FIN) {
                    sendAck(socketFD, msg);
                    sendFin(socketFD);
                    updateState(socketFD, CLOSED);
                }
                break;

            case SYN_SENT:
                if (header.flag == ACK) {
                    updateState(socketFD, ESTABLISHED);
                }
                else if (header.flag == SYN) {
                    sendAck(socketFD, msg);
                }
                else {
                    dbg(TRANSPORT_CHANNEL, "[Error] recieve: Invalid packet type for SYN_SENT state\n");
                }
                break;

            case SYN_RCVD:
                if (header.flag == ACK) {   
                    updateState(socketFD, ESTABLISHED);
                }
                else {
                    dbg(TRANSPORT_CHANNEL, "[Error] recieve: Invalid packet type for SYN_RCVD state\n");
                }
                break;

            default:
                getState(socket.state, dbg_string);
                dbg(TRANSPORT_CHANNEL, "[Error] recieve: Invalid socket state %s\n", dbg_string);
        }
    }

    /* SECTION: Events */

    // TODO: Remove or refactor
    // event void SrcTimeout.fired(){
        
    // }

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
            dbg (TRANSPORT_CHANNEL, "[Error] sendSyn: Invalid file descriptor\n");
            return;
        }

        socket = call SocketMap.get(socketFD);

        synPack.src = TOS_NODE_ID;
        synPack.dest = socket.dest.addr;
        synPack.seq = signal TCPHandler.getSequence();
        synPack.TTL = MAX_TTL;
        synPack.protocol = PROTOCOL_TCP;

        syn_header.src_port = socket.src;
        syn_header.dest_port = socket.dest.port;
        syn_header.flag = SYN;
        syn_header.seq = socket.lastWritten + 1;
        syn_header.advert_window = socket.effectiveWindow;

        memcpy(&synPack.payload, &syn_header, TCP_PAYLOAD_SIZE);

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
            dbg(TRANSPORT_CHANNEL, "[Error] sendAck: Invalid file descriptor\n");
            return;
        }

        socket = call SocketMap.get(socketFD);

        // Retrieve the TCP header from the original message
        memcpy(&originalHeader, &(original_message->payload), PACKET_MAX_PAYLOAD_SIZE);

        ackPack.src = TOS_NODE_ID;
        ackPack.dest = socket.dest.addr;
        ackPack.seq = signal TCPHandler.getSequence();
        ackPack.TTL = MAX_TTL;
        ackPack.protocol = PROTOCOL_TCP;

        ackHeader.src_port = socket.src;
        ackHeader.dest_port = socket.dest.port;
        ackHeader.seq = socket.nextExpected; // REVIEW: Maybe not the correct value
        ackHeader.advert_window = socket.effectiveWindow;
        ackHeader.flag = ACK;

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
            dbg(TRANSPORT_CHANNEL, "[Error] sendFin: Invalid file descriptor\n");
            return;
        }

        socket = call SocketMap.get(socketFD);

        finPack.src = TOS_NODE_ID;
        finPack.dest = socket.dest.addr;
        finPack.seq = signal TCPHandler.getSequence();
        finPack.TTL = MAX_TTL;
        finPack.protocol = PROTOCOL_TCP;

        fin_header.src_port = socket.dest.port;
        fin_header.dest_port = socket.src;
        fin_header.seq = socket.lastWritten + 1;
        fin_header.advert_window = socket.effectiveWindow;
        fin_header.flag = FIN;

        memcpy(&finPack.payload, &fin_header, PACKET_MAX_PAYLOAD_SIZE);
                                                                                                       
        write(socketFD, &finPack);                
    }    

    /** NOTE: Temp function so it compiles */
    event void SrcTimeout.fired() {}
}
