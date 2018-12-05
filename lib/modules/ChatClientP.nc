    #include <stdlib.h>
    #include <stdio.h>
    #include "../../includes/socket.h"
    #include "../../includes/packet.h"

    
module ChatClientP{

    uses interface List<socket_store_t> as UsrList;
}
implementation  {
    //SECTION: project 4 implementation

    command void ChatClient.Connect(){
        socket_store_t socket;
        //socket = signal TCPHandler.connect();
        //FIXME: thinking signaling TCPHandlerjust to connect to a nodes so we would need sockets

       //FIXME: dbg(GENERAL_CHANNEL, "hello \r\n", ); //should print hello "[username][clientport]"
    }

    command void ChatClient.Broadcast(){
        //FIXME: parameters should be maybe a packet and socket type?


        //FIXME: dbg(GENERAL_CHANNEL, "msg \r\n", ); // should display msg contents with packet pointer to payload
    }

    command void ChatClient.Whisper(){
        //FIXME: shoudl send messges directly to a certain user
        // TODO: so with the knowledge of knowing your neighbors you can diractly send a message to the user  

        //FIXME: dbg(GENERAL_CHANNEL, "whisper \r\n", ); // should display [username][message] so 
    }

    command void ChatClient.PrintUsr(){
        //FIXME with the list of users that the server is connected to 
        uint_16 i;
        for(i = 0; i < UsrList.size(); i++){
            //dbg(GENERAL_CHANNEL, "listusr \r\n", )) // 
        }
        

    }
}