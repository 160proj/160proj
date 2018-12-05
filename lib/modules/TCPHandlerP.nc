#include <stdlib.h>
#include <stdio.h>
#include <Timer.h>
#include "../../includes/socket.h"
#include "../../includes/packet.h"
#include "../../includes/tcp_header.h"

module TCPHandlerP {
    provides interface TCPHandler;

    uses interface Timer<TMilli> as PacketTimer;
    uses interface Hashmap<socket_store_t> as SocketMap;
    uses interface List<socket_store_t> as ServerList;
    uses interface List<pack> as CurrentMessages;
    
}


implementation {
    /* SECTION: Member Variables */

    socket_t next_fd = 1; /** Next open file descriptor to bind a socket to */
    uint16_t* node_seq; /** Pointer to node's sequence number */
    const uint16_t default_rtt = 1500; /** The default RTT for the sockets */
    uint8_t temp_buffer[TCP_PAYLOAD_SIZE]; /** Temporary buffer for storing message data */

    /* SECTION: Prototypes */

    void sendSyn(socket_t socketFD);
    void sendAck(socket_t socketFD, pack* original_message);
    void sendFin(socket_t socketFD);
    void sendDat(socket_t socketFD, uint8_t* data, uint16_t size);

    void send(socket_t socketFD, uint32_t transfer);
    void write(socket_t socketFD, pack* msg);
    void sendNext();
    void sendNextFromSocket(socket_t socketFD);

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
    socket_t connect(uint16_t dest, uint16_t srcPort, uint16_t destPort) {
        uint16_t size = call ServerList.size();
        uint16_t i;

        for (i = 0; i < size; i++) {
            socket_store_t socket = call ServerList.get(i);

            if (socket.src == srcPort) {
                    // Make copy of the server socket for the connection
                    socket_store_t new_socket = socket;
                    new_socket.state = LISTEN;
                    new_socket.dest.addr = dest;
                    new_socket.dest.port = destPort;
                    memset(new_socket.rcvdBuff, 255, SOCKET_BUFFER_SIZE);
                    return addSocket(new_socket);
            }
        }

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
     * Checks if a sequence number has been acknowledged.
     *
     * @param socketFD the file descripter for the socket.
     * @param seq the sequence number to check.
     *
     * @return true if the sequence has been acked, false if it has not.
     */
    bool isAcked(socket_t socketFD, uint16_t seq) {
        socket_store_t socket;

        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] isAcked: Invalid file descriptor\n");
            return FALSE;
        }

        socket = call SocketMap.get(socketFD);

        if (seq == 65535) { // SYN/FIN packets (special case in this implementation)
            return socket.state == SYN_RCVD
                || socket.state == ESTABLISHED
                || socket.state == CLOSED;
        }

        if (socket.lastAck < socket.lastSent) { // Normal Case
            return seq > socket.lastSent || seq <= socket.lastAck;
        }
        else { // Wraparound
            return seq > socket.lastSent && seq <= socket.lastAck;
        }
    }

    /**
     * Checks if a sequence number has been read.
     *
     * @param socketFD the file descripter for the socket.
     * @param seq the sequence number to check.
     *
     * @return true if the sequence has been read, false if it has not.
     */
    bool isRead(socket_t socketFD, uint16_t seq) {
        socket_store_t socket;

        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] isRead: Invalid file descriptor\n");
            return FALSE;
        }

        socket = call SocketMap.get(socketFD);

        if (socket.lastRcvd < socket.lastRead) { // Normal Case
            return seq >= socket.lastRead || seq < socket.lastRcvd;
        }
        else { // Wraparound
            return seq >= socket.lastRead && seq < socket.lastRcvd;
        }
    }

    /**
     * Checks if a sequence number has been written.
     *
     * @param socketFD the file descripter for the socket.
     * @param seq the sequence number to check.
     *
     * @return true if the sequence has been written, false if it has not.
     */
    bool isWritten(socket_t socketFD, uint16_t seq) {
        socket_store_t socket;

        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] isWritten: Invalid file descriptor\n");
            return FALSE;
        }

        socket = call SocketMap.get(socketFD);

        if (socket.lastAck < socket.lastWritten) { // Normal Case
            return seq >= socket.lastWritten || seq < socket.lastAck;
        }
        else { // Wraparound
            return seq >= socket.lastWritten && seq < socket.lastAck;
        }
    }

    /**
     * Sends the message through the socket. Use instead of sendNextFromSocket.
     *
     * @param socketFD the file descriptor for the socket.
     * @param msg the packet to send.
     */
    void write(socket_t socketFD, pack* msg) {
        socket_store_t socket;

        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] write: Invalid file descriptor\n");
            return;
        }
        
        socket = call SocketMap.get(socketFD);
        call CurrentMessages.pushfrontdrop(*msg);
        sendNextFromSocket(socketFD);             

        updateSocket(socketFD, socket);
    }

    /**
     * Fills the send buffer with the bytes to send
     * Will resume filling if all bytes did not fit.
     *
     * @param socketFD the file descriptor for the socket.
     * @param transfer the number of bytes to send with values (0..transfer-1)
     *
     * @return the number of bytes of 'transfer' were able to fit into the buffer.
     */
    uint32_t fill(socket_t socketFD, uint32_t transfer) {
        socket_store_t socket;
        uint8_t start;
        uint8_t end;
        uint32_t i;

        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] fill: Invalid file descriptor\n");
            return 0;
        }

        socket = call SocketMap.get(socketFD);

        start = socket.lastSent + 1;
        end = socket.lastAck - 1;
        if (transfer == 0) {
            transfer = socket.flag + socket.sendBuff[start-1];
        }
        // Bound the start value
        if (start >= SOCKET_BUFFER_SIZE) {
            start = 0;
        }

        // Bound the end value
        if (end >= SOCKET_BUFFER_SIZE) {
            end = SOCKET_BUFFER_SIZE;
        }

        for (i = 0; i < transfer - socket.flag; i++) {
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
                if (socket.flag - i > 0) {
                    socket.flag -= i;
                } else {
                    socket.flag = 0;
                }
                updateSocket(socketFD, socket);
                return i;
            }
        }

        return 0;
    }

    /**
     * Prints the contents of a packet's payload
     */
    void printUnread(socket_t socketFD) {
        socket_store_t socket;
        uint16_t i;
        uint16_t count = 0;
        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] printPayload: Invalid file descriptor\n");
            return;
        }

        socket = call SocketMap.get(socketFD);
        
        for (i = socket.lastRead+1; !isRead(socketFD, i); i++) {
            if (i >= SOCKET_BUFFER_SIZE) {
                i = 0;
            }
            if (count > SOCKET_BUFFER_SIZE) {
                break;
            }
            // dbg(TRANSPORT_CHANNEL, "%hu\n", i);
            if (!isRead(socketFD, i)) {
                dbg(GENERAL_CHANNEL, "%d, \n", socket.rcvdBuff[i]);
                socket.lastRead = i;
            }
            count++;
        }
        updateSocket(socketFD, socket);
    }

    // /**
    //  * Sends the next packet in the CurrentMessages.
    //  */
    // void sendNext() {
    //     pack packet;
    //     tcp_header header;
    //     socket_store_t socket;
    //     socket_t socketFD;
    //     uint16_t i;

    //     if (!call CurrentMessages.isEmpty()) {
    //         return;
    //     }

    //     packet = call CurrentMessages.front();
    //     memcpy(&header, &packet.payload, PACKET_MAX_PAYLOAD_SIZE);

    //     socketFD = getFD(packet.dest, header.src_port, header.dest_port);

    //     if (!socketFD) {
    //         dbg(TRANSPORT_CHANNEL, "[Error] sendNext: Invalid file descriptor\n");
    //         return;
    //     }

    //     socket = call SocketMap.get(socketFD);

    //     signal TCPHandler.route(&packet);
    //     call PacketTimer.startOneShot(call PacketTimer.getNow() + 2*socket.RTT);
    // }

    /**
     * Sends the next packet for the socket.
     *
     * @param socketFD the file descriptor for the socket.
     */
    void sendNextFromSocket(socket_t socketFD) {
        pack packet;
        tcp_header header;
        socket_store_t socket;
        uint16_t i;

        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] sendNextFromSocket: Invalid file descriptor\n");
            return;
        }

        socket = call SocketMap.get(socketFD);

        packet = call CurrentMessages.front();
        memcpy(&header, &packet.payload, PACKET_MAX_PAYLOAD_SIZE);

        signal TCPHandler.route(&packet);
        call PacketTimer.startOneShot(call PacketTimer.getNow() + 2*socket.RTT);
    }

    /**
     * Sends the next data packet for the socket.
     *
     * @param socketFD the file descriptor for the socket.
     */
    void sendNextData(socket_t socketFD) {
        pack packet;
        tcp_header header;
        socket_store_t socket;
        uint16_t i;


        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] sendNextFromSocket: Invalid file descriptor\n");
            return;
        }

        socket = call SocketMap.get(socketFD);
        
        memcpy(temp_buffer, socket.sendBuff+socket.lastSent, TCP_PAYLOAD_SIZE);

        for (i = 0; i < SOCKET_BUFFER_SIZE; i++) {
            dbg(TRANSPORT_CHANNEL, "%hhu\n", socket.sendBuff[i]);
        }
        dbg(TRANSPORT_CHANNEL, "----------%hhu\n", *(socket.sendBuff+socket.lastSent));

        sendDat(socketFD, temp_buffer, TCP_PAYLOAD_SIZE);
        call PacketTimer.startOneShot(call PacketTimer.getNow() + 2*socket.RTT);
    }

    /**
     * Removes the message corresponding to the header
     *
     * @param ack_header the header for the received ack packet.
     */
    void removeAck(tcp_header ack_header) {
        uint16_t i;
        uint16_t size = call CurrentMessages.size();

        for (i = 0; i < size; i++) {
            pack tempPack = call CurrentMessages.get(i);
            tcp_header tempHeader;
            memcpy(&tempHeader, &tempPack.payload, PACKET_MAX_PAYLOAD_SIZE);

            if (tempHeader.seq == ack_header.seq &&
                tempHeader.dest_port == ack_header.src_port) {
                    call CurrentMessages.remove(i);
                    return;
            }
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
            dbg(TRANSPORT_CHANNEL, "[Error] startServer: Cannot create server at Port %hhu: Max num of sockets reached\n", port);
        }

        socket.src = port;
        socket.state = LISTEN;
        socket.dest.addr = ROOT_SOCKET_ADDR;
        socket.dest.port = ROOT_SOCKET_PORT;
        socket.effectiveWindow = 1;
        socket.flag = 0;
        socket.RTT = default_rtt;

        call ServerList.pushbackdrop(socket);
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
        socket_t socketFD;

        socket.src = srcPort;
        socket.dest.port = destPort;
        socket.dest.addr = dest;
        socket.state = SYN_SENT;
        socket.lastWritten = SOCKET_BUFFER_SIZE;
        socket.lastAck = SOCKET_BUFFER_SIZE;
        socket.lastSent = SOCKET_BUFFER_SIZE;
        socket.effectiveWindow = 1;
        socket.RTT = default_rtt;
        memset(socket.sendBuff, '\0', SOCKET_BUFFER_SIZE);

        socketFD = addSocket(socket);
        socket.flag = fill(socketFD, transfer);
        updateSocket(socketFD, socket);
        sendSyn(socketFD);

        dbg(TRANSPORT_CHANNEL, "Client started on Port %hhu with destination %hu: %hhu\n", srcPort, dest, destPort);
        dbg(TRANSPORT_CHANNEL, "Transferring %hu bytes to destination...\n", transfer);
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
            connect(msg->src, header.dest_port, header.src_port);
        }

        socketFD = getFD(msg->src, header.dest_port, header.src_port);

        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] recieve: No socket associated with message from Node %hu\n", msg->src);
            return;
        }

        socket = call SocketMap.get(socketFD);

        // if(header.flag != DAT) {
            dbg(TRANSPORT_CHANNEL, "--- TCP Packet recieved ---\n");
            logPack(msg);
            logHeader(&header);
            dbg(TRANSPORT_CHANNEL, "--------- Socket ----------\n");
            logSocket(&socket);
            dbg(TRANSPORT_CHANNEL, "---------------------------\n\n");
        // }

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
                    updateState(socketFD, SYN_RCVD);
                }
                break;

            case ESTABLISHED:
                if (header.flag == DAT) {
                    if (isAcked(socketFD, header.seq)) {
                        break;
                    }
                    sendAck(socketFD, msg);
                    memcpy(&socket.rcvdBuff+socket.lastRead+1, &header.payload, header.payload_size);
                    socket.lastRcvd = socket.lastRead + header.payload_size;
                    if (socket.lastRead + header.payload_size >= SOCKET_BUFFER_SIZE) {
                        socket.lastRcvd = socket.lastRead+header.payload_size - SOCKET_BUFFER_SIZE;
                        memcpy(socket.rcvdBuff, socket.rcvdBuff+SOCKET_BUFFER_SIZE, socket.lastRcvd);
                    }
                    // FIXME: Fix the wraparound issue
                    updateSocket(socketFD, socket);
                    printUnread(socketFD);
                }
                else if (header.flag == ACK) {
                    call PacketTimer.stop();
                    removeAck(header);
                    // TODO: Update RTT
                    fill(socketFD, 0);
                    socket.nextExpected = header.seq+1;
                    sendNextData(socketFD);
                }
                else if (header.flag == FIN) {
                    sendAck(socketFD, msg);
                    sendFin(socketFD);
                    updateState(socketFD, CLOSED);
                }
                break;

            case SYN_SENT:
                
                if (header.flag == ACK) {
                    updateState(socketFD, ESTABLISHED);
                    call PacketTimer.stop();
                    removeAck(header);
                    sendNextData(socketFD);
                    // TODO: Update RTT
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
                    call PacketTimer.stop();
                    removeAck(header);
                    // TODO: Update RTT
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

    /**
     * Timeout on packet acks.
     * Fires if a packet has not recieved an ack by its timeout.
     */
    event void PacketTimer.fired(){
        pack packet;
        tcp_header header;
        socket_store_t socket;
        socket_t socketFD;

        if (!call CurrentMessages.isEmpty()) {
            return;
        }

        packet = call CurrentMessages.front();
        memcpy(&header, &packet.payload, PACKET_MAX_PAYLOAD_SIZE);

        socketFD = getFD(packet.dest, header.src_port, header.dest_port);

        if (!socketFD) {
            dbg(TRANSPORT_CHANNEL, "[Error] PacketTimer.fired: Invalid file descriptor\n");
            return;
        }

        socket = call SocketMap.get(socketFD);

        // Packed was acked, send the next one
        while(isAcked(socketFD, header.seq)) {
            call CurrentMessages.remove(0);
            if (call CurrentMessages.isEmpty()) {
                return;
            }
            packet = call CurrentMessages.front();
            
            memcpy(&header, &packet.payload, PACKET_MAX_PAYLOAD_SIZE);
            socketFD = getFD(packet.dest, header.src_port, header.dest_port);

            if (!socketFD) {
                dbg(TRANSPORT_CHANNEL, "[Error] PacketTimer.fired: Invalid file descriptor\n");
                return;
            }  

            socket = call SocketMap.get(socketFD);          
        }

        if (!call CurrentMessages.isEmpty()) {
            signal TCPHandler.route(&packet);
            call PacketTimer.startOneShot(call PacketTimer.getNow() + 2*socket.RTT);
        }
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
        syn_header.seq = 65535;
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
        ackHeader.seq = originalHeader.seq; // REVIEW: Maybe not the correct value
        ackHeader.advert_window = socket.effectiveWindow;
        ackHeader.flag = ACK;
        ackHeader.payload_size = 0;
        memset(&ackHeader.payload, '\0', TCP_PAYLOAD_SIZE);

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

        fin_header.src_port = socket.src;
        fin_header.dest_port = socket.dest.port;
        fin_header.seq = 65535;
        fin_header.advert_window = socket.effectiveWindow;
        fin_header.flag = FIN;

        memcpy(&finPack.payload, &fin_header, PACKET_MAX_PAYLOAD_SIZE);
                                                                                                       
        write(socketFD, &finPack);                
    }

    /**
     * Sends a data packet to the destination.
     *
     * @param socketFD the file descriptor for the socket.
     */
    void sendDat(socket_t socketFD, uint8_t* data, uint16_t size) {
        socket_store_t socket;
        pack datPack;
        tcp_header dat_header;
        uint16_t i;
                        
        if (!socketFD) {
            dbg (TRANSPORT_CHANNEL, "[Error] sendDat: Invalid file descriptor\n");
            return;
        }

        socket = call SocketMap.get(socketFD);

        datPack.src = TOS_NODE_ID;
        datPack.dest = socket.dest.addr;
        datPack.seq = signal TCPHandler.getSequence();
        datPack.TTL = MAX_TTL;
        datPack.protocol = PROTOCOL_TCP;

        dat_header.src_port = socket.src;
        dat_header.dest_port = socket.dest.port;
        dat_header.flag = DAT;
        dat_header.seq = socket.nextExpected;
        dat_header.advert_window = socket.effectiveWindow;
        dat_header.payload_size = size;

        memcpy(&dat_header.payload, temp_buffer, size);

        for(i = 0; i < size; i++) {
            dbg(TRANSPORT_CHANNEL, "\t%hhu\n", temp_buffer[i]);
        }

        memcpy(&datPack.payload, &dat_header, TCP_PAYLOAD_SIZE);

        write(socketFD, &datPack);
    } 



}