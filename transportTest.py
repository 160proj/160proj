from TestSim import TestSim

def main():
    # Get simulation ready to run.
    s = TestSim()

    # Before we do anything, lets simulate the network off.
    s.runTime(1)

    # Load the the layout of the network.
    s.loadTopo("long_line.topo")

    # Add a noise model to all of the motes.
    s.loadNoise("no_noise.txt")

    # Turn on all of the sensors.
    s.bootAll()

    # Add the main channels. These channels are declared in includes/channels.h
    s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.GENERAL_CHANNEL)
    s.addChannel(s.TRANSPORT_CHANNEL)

    # Regular let all the routing tables settle
    s.runTime(100)

    s.testServer(address=10, port=33)

    s.runTime(5)
    
    s.testClient(clientAddress=2, dest=10, srcPort=20, destPort=33, transfer=30)

    s.runTime(10)

    s.closeClient(clientAddress=2, dest=10, srcPort=20, destPort=33)
    
    
if __name__ == '__main__':
    main()