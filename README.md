This is a Stomp Implementation for TCL: tStomp
Version 0.2

Stomp stands for "Streaming Text Orientated Messaging Protocol". 
  This implementation is based on Stomp 1.1 specification, which can be found at 
  http://stomp.github.com/stomp-specification-1.1.html
  TCL homepage: http://www.tcl.tk/

Primary site:
  https://github.com/siemens/tstomp/

Source code at:
  https://github.com/siemens/tstomp/

How to run tStomp:
  configure Apache ActiveMQ:
    edit activemq.xml
    add transport connectors:
       <transportConnectors>
            <transportConnector name="openwire" uri="tcp://0.0.0.0:61616"/>
            <transportConnector name="stomp" uri="stomp://0.0.0.0:61613"/>
        </transportConnectors>
        
Running unit tests:
  start tcl console, source e.g. tStompClientQueue.test 

Running load tests:
  start JMeter (https://jmeter.apache.org), load ActiveMQPublishSubscribe.jmx
  
Documentation:
  currently just unit tests available, see tcltest files tStomp*.test for usage!

History
  Initial Version 0.1:
    by Sravanthi Anumakonda, Derk Muenchhausen
  Version 0.2:
    improved protocol state machine by Franziska Haunolder

