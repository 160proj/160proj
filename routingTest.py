from TestSim import TestSim

def main():
    # Get simulation ready to run.
    s = TestSim();

    # Before we do anything, lets simulate the network off.
    s.runTime(1);

    # Load the the layout of the network.
    s.loadTopo("long_line.topo");

    # Add a noise model to all of the motes.
    s.loadNoise("no_noise.txt");

    # Turn on all of the sensors.
    s.bootAll();

    # Add the main channels. These channels are declared in includes/channels.h
    s.addChannel(s.COMMAND_CHANNEL);
    s.addChannel(s.GENERAL_CHANNEL);
    s.addChannel(s.ROUTING_CHANNEL);

    s.runTime(600);

    for i in range(1, 10):
        s.routeDMP(i);
        s.runTime(5);


    s.neighborDMP(5);
    s.runTime(1);
    s.routeDMP(5);
    s.runTime(5);

    s.neighborDMP(2);
    s.runTime(1);
    s.routeDMP(2);
    s.runTime(5);

    s.neighborDMP(9);
    s.runTime(1);
    s.routeDMP(9);
    s.runTime(5);

    s.ping(1, 9, "Test");
    s.runTime(5);
    
    s.moteOff(3);
    s.runTime(600);
    
    s.neighborDMP(5);
    s.runTime(1);
    s.routeDMP(5);
    s.runTime(5);

    s.neighborDMP(9);
    s.runTime(1);
    s.routeDMP(9);
    s.runTime(5);

    s.neighborDMP(1);
    s.runTime(1);
    s.routeDMP(1);
    s.runTime(5);

    s.ping(1, 9, "Test");
    s.runTime(5);

if __name__ == '__main__':
    main()
