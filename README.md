This is a Stomp Implementation for TCL: tStomp

Version 0.4

Stomp stands for "Streaming Text Orientated Messaging Protocol".  
  This implementation is based on Stomp 1.1 specification, which can be found at http://stomp.github.com/stomp-specification-1.1.html  
  TCL homepage: http://www.tcl.tk/ 

Primary site:
  https://github.com/siemens/tstomp/

Source code:
  https://github.com/siemens/tstomp.git

# How to run tStomp
* configure Apache ActiveMQ:
    * edit activemq.xml
    * add transport connectors:

    ```
       <transportConnectors>
            <transportConnector name="openwire" uri="tcp://0.0.0.0:61616"/>
            <transportConnector name="stomp" uri="stomp://0.0.0.0:61613"/>
        </transportConnectors>
    ```
* Running unit tests:
    * start tcl console, source e.g. tStomp.test 

* Running load tests:
    * start JMeter (https://jmeter.apache.org), load ActiveMQPublishSubscribe.jmx, start tcl console and config and source EchoTest.tcl
  
# Documentation
  currently just unit tests available, see tcltest files tStomp*.test for usage!

# History
*  Version 0.4 2012-08-17:
     * automatic reconnect
     * unsubscribe bug
     * utf-8 encoding bug
     * small changes for unix by Francisco Castro
*  Version 0.3 2012-06-13:
     * improved unit test cases by Christian Ringhut and Jan Schimanski
     * compatible with ActiveMQ 5.6.0 by Alexander Vetter
*  Version 0.2 2012 2012-01-10:
     * improved protocol state machine by Franziska Haunolder
* Initial Version 0.1 2011-09-28:
     * by Sravanthi Anumakonda, Derk Muenchhausen
