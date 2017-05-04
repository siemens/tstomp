# tStomp [![Build Status](https://travis-ci.org/siemens/tstomp.svg?branch=master)](https://travis-ci.org/siemens/tstomp)
This is a Stomp Implementation for Tcl coded in pure Tcl.

**Current Version 0.10**

Stomp stands for "Streaming Text Orientated Messaging Protocol". This implementation is based on Stomp 1.2 specification, which can be found at [stomp.github.com](http://stomp.github.com/stomp-specification-1.2.html). For futher information about Tcl, visit their homepage at [Tcl Developer Xchange](http://www.tcl.tk).

Primary site: https://github.com/siemens/tstomp

Source code: https://github.com/siemens/tstomp.git

## How to run tStomp
* download ActiveMQ Version >= 5.9.0 from http://activemq.apache.org/
* configure Apache ActiveMQ:
    * edit activemq.xml
    * add transport connectors:

``` xml
<transportConnectors>
	...     
	<transportConnector name="stomp" uri="stomp://0.0.0.0:61613"/>
</transportConnectors>
```
* Running integration tests:
set the environment variable stompServerURL to your Broker, start tcl console and run
    
``` tcl
source tStompTestIntegration.tcl
```
* or run it in under e.g. under Windows in CMD Box 
	
``` bat
set stompServerURL=stomp://system:manager@yourBrokerHost:61613
set TCLLIBPATH="C:/yourLibPath/noarch"
cd c:\yourTclInstallation
.\tclsh.exe noarch\tstomp\tStompTestIntegration.tcl
``` 

* Running load tests:
start JMeter (https://jmeter.apache.org), load ActiveMQPublishSubscribe.jmx, start tcl console and config and source EchoTest.tcl
  
## Tutorial	

tStomp is a TCL implementation of the STOMP protocol. You can connect to a message broker, publish and subscribe to queues and topics.
	
To use tStomp, at first a connection to the Broker must be established. All information about the Broker is given by a stompUrl to tStomp. The stompUrl must have the format
	
	stomp://username:password@host:port

or more advanced connction string for failover:

	failover:(stomp:tcp://username:password@activemqhost1:61613,stomp:tcp://username:password@activemqhost2:61613)
		
Create a tStomp object and connect to a broker:
``` tcl		
tStomp tStomp_instance $stompUrl
tStomp_instance connect {puts "connection established to $host $port"} 
```			
After connection is established tStomp is able to publish messages and subscribe to queues.
``` tcl	
tStomp_instance send "/queue/exampleQueue" "best whishes!"
```	
The send command has some optional arguments:
``` tcl
	-ttl <time-to-live-in-milliseconds>
	-correlationId <id>
	-replyTo <queueName>
	-persistent true|false
	-headers <name-value-list>  # The parameters ttl, correlationId, replyTo and persistent will overwrite the corresponding headers.	
```		
e.g.:
``` tcl
tStomp_instance send -ttl 300000 -replyTo "/queue/replyToQueue" -headers [list correlationId 1 content-type String] "/queue/exampleQueue" "best whishes!"
```	
If a option is set the header will be ignored.
``` tcl	
tStomp_instance send -replyTo "/queue/replyToQueue" -headers [list reply-to "/queue/IgnoredQueue"] "/queue/exampleQueue" "message"
```	
The option/header ttl is an exception. The ActiveMQ Broker does only have expires as the Expiration Time. It does not support ttl. If the header/option ttl is set a header expires will be generated.
If the header expires is set, the header ttl will be ignored, the option ttl will overwrite it though. A ttl of 0 will result in an Expiration Time of 0, meaning it will not expire.
``` tcl			
tStomp_instance send -ttl 300000 "/queue/exampleQueue" "message" -> Expiration Time 300 seconds from now
tStomp_instance send -headers [list expires 300000] "/queue/exampleQueue" "message" -> Expiration Time 300 seconds from now
tStomp_instance send -ttl 300000 -headers [list ttl 150000] "/queue/exampleQueue" "message" -> Expiration Time 300 seconds from now
tStomp_instance send -headers [list ttl 150000 expires 300000] "/queue/exampleQueue" "message" -> Expiration Time 300 seconds from now
tStomp_instance send -ttl 300000 -headers [list expires 150000] "/queue/exampleQueue" "message" -> Expiration Time 300 seconds from now

tStomp_instance send -headers [list ttl 0] "/queue/exampleQueue" "message" -> Expiration Time 0, the message will not expire
tStomp_instance send -headers [list expires 0] "/queue/exampleQueue" "message" -> Expiration Time 0, the message will not expire
tStomp_instance send -ttl 0 "/queue/exampleQueue" "message" -> Expiration Time 0, the message will not expire
```		
** it is important that the Broker and tStomp run on the same timezone or else the difference is calculated **
		
Subscribing to a queue will enable to receive messages which are sent to that queue. Every time a message is received the callBackScript is called.
``` tcl	
tStomp_instance subscribe "/queue/subscribeQueue" {puts "message received"}
```		
After a broker failover, all subscribe commands will be re-executed. 	
	
The unsubscribe method unsubscribes from the given queue and erases the correlating callBackScript.
``` tcl	
tStomp_instance unsubscribe "/queue/exampleQueue"
```	
To disconnect the disconnect method may be called. It is possible to force the disconnect with the parameter force. If force is set the notConnected error is ignored.
``` tcl	
tStomp_instance disconnect -> force = 0
tStomp_instance disconnect 1 -> force = 1
```		

## Heart Beat Implementation
A first step towards Stomp 1.2 compatibility is the implementation of heart beat messages. With tStomp it is possible to ask the server for sending periodic heart beats. About all heartBeatExpected (in ms) the script heartBeatScript will be called. If the connection get's lost, a reconnection is triggered. 
``` tcl
tStomp_instance connect {puts "CONNECTED"} -heartBeatScript {puts "heart beat isConnected=$isConnected host=$host port=$port"}  -heartBeatExpected 1000
```

## Error Handling
tStomp has 4 errors implemented:
		
* alreadyConnected: thrown if connect is called while already connected
* notConnected: thrown if trying to disconnect, send or unsubscribe while not connected
* wrongArgs: thrown if a method is called with wrong arguments
* notSubscribedToGivenDestination: thrown if trying to unsubscribe from a destination while not subscribed

## API
```
class tStomp

	constructor {stompUrl}
		Standard Stomp URL format is possible - e.g.:
		stomp://username:password@host:port
		failover:(stomp:tcp://username:password@activemqhost1:61613,stomp:tcp://username:password@activemqhost2:61613)

	destructor {}
		Called when objects of the class are deleted

	public connect {onConnectScript args}
		connects to given stompUrl in the constructor. 
		onConnectScript is called after connection is confirmed. 
		Optional parameters 
			-heartBeatScript <script> 	# script to be called after receifing heartBeat. The local variables isConnected, host and port indicate the current connection state.
			-heartBeatExpected <heartBeatExpected> # heart beat expected every <heartBeatExpected> ms.  
			-reconnect <reconnection>	# reconnection 0|1 - use previous parameters. Default 0.
			-supervisionTime <supervisionTime>  # after a connection, no reconnect is allowed within <supervisionTime> (in sec)

	public disconnect {force 0}
		disconnects from server

	public send {dest msg args}
		publishes a message msg to destination dest. 
		Optional parameters 
			-correlationId <correlationId>
			-replyTo <queue>
			-persistent <persistent>
			-ttl <ttl>
			-headers <headerList>
		if an option and a header exists, the header will be overwritten by the option

	public subscribe {destName callbackscript}
		Command is used to register to listen to a given destination. On every received message callbackscript will be called

	public unsubscribe {destName}
		unsubscribes the given destination. correlating callbackscript will be removed

	public getStompVersion {}
		returns the current stomp version

	public getIsConnected {}
		returns if the tStomp is connected

	public setWriteSocketFile {status}
		set to enable logging. tStomp log is written in tStomp.log . if nothing is set logging is disabled

	proc setDebugCmd {script} 
		injects a custom debug output command - e.g.
		tStomp::setDebugCmd {::debug $msg $level}
		tStomp::setDebugCmd {trace $msg}
```
Integration Tests can be found in [tStompTestIntegration.tcl](https://github.com/siemens/tstomp/blob/master/tStompTestIntegration.tcl).
		

# History
*  Version 0.9 2016-02-04:
	 * added supervision support: after a connection, no reconnect is allowed within supervisionTime period 
*  Version 0.8 2015-04-18:
     * added support for simple failover 
     * signature of execute_thread extended by parameters isConnected, host and port !
     * tested with ActiveMQ 5.9 and ActiveMQ 5.11.1
*  Version 0.7 2015-03-29:
	 * implementation of server initiated heart beats for upcomming Stomp 1.2 specification
*  Version 0.6 2014-03-05:
     * add support for additional headers (connect, subscribe, unsubscribe)
     * test for durable subscription
     * fix a problem with parsing header containing a \c
*  Version 0.5 2013-10-21:
	 * parse stompUrl
	 * new options in tStomp send
	 * bugfixes
	 * newline in messagebody support
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

