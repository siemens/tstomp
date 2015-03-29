# tStomp
This is a Stomp Implementation for Tcl coded in pure Tcl.

**Current Version 0.7**

Stomp stands for "Streaming Text Orientated Messaging Protocol". This implementation is based on Stomp 1.1 specification, which can be found at http://stomp.github.com/stomp-specification-1.1.html. For futher information about Tcl, visit their homepage at http://www.tcl.tk.

Primary site: https://github.com/siemens/tstomp
Source code: https://github.com/siemens/tstomp.git

## How to run tStomp
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
  
## Tutorial	

As the TCL implementation of STOMP the tStomp is able to connect to a message broker to send, receive and handle asynchronous messages.
	
To use tStomp, at first a connection to the Broker must be established. All information about the Broker is given by a stompUrl to tStomp. The stompUrl must have the format
	
	stomp://username:password@host:port
		
When creating an object of tStomp the stompUrl is given as a parameter. tStomp splits the stompUrl and saves host, port, username and password in local variables.
		
	tStomp tStomp_instance $stompUrl
		
The connect method uses the information in the variables to establish the connection. A callBackScript is given which is called as soon as the connection is established.
	
	tStomp_instance connect {puts "connection established"}
		
A simple test to see if the connection is established in a certain time:
		
	tStomp_instance connect {set ::result CONNECTED}
	after 5000 [list set ::result "NOT CONNECTED"]
	vwait ::result
	if {$::result == "NOT CONNECTED"} {
		error "In testcase 'Stomp_connect' Connection failed"
		puts "### NOT CONNECTED"
	}
	
After connecting tStomp is able to either send messages and subscribe to queues.
	
To send a message different headers may be given. Possible options are:
	
	-ttl (time to live) in milliseconds
	-correaltionId
	-replyTo
	-persistent
	-headers -> a list in which all other headers are given
	
The only header the send command does need is destination. The simplest send command would be:
	
	tStomp_instance send "/queue/exampleQueue"
		
With a given message:
		
	tStomp_instance send "/queue/exampleQueue" ""
		
	tStomp_instance send "/queue/exampleQueue" "message"
		
With other headers:
		
	tStomp_instance send -ttl 300000 -replyTo "/queue/replyToQueue" -headers [list correlationId 1 content-type String] "/queue/exampleQueue" "message"
		
If a option is set the header will be ignored.
		
	tStomp_instance send -replyTo "/queue/replyToQueue" -headers [list reply-to "/queue/IgnoredQueue"] "/queue/exampleQueue" "message"
	
The option/header ttl is an exception. The ActiveMQ Broker does only have expires as the Expiration Time. It does not support ttl. If the header/option ttl is set a header expires will be generated.
If the header expires is set, the header ttl will be ignored, the option ttl will overwrite it though.
		
	tStomp_instance send -ttl 300000 "/queue/exampleQueue" "message" -> Expiration Time 300 seconds from now
	tStomp_instance send -headers [list expires 300000] "/queue/exampleQueue" "message" -> Expiration Time 300 seconds from now
	tStomp_instance send -ttl 300000 -headers [list ttl 150000] "/queue/exampleQueue" "message" -> Expiration Time 300 seconds from now
	tStomp_instance send -headers [list ttl 150000 expires 300000] "/queue/exampleQueue" "message" -> Expiration Time 300 seconds from now
	tStomp_instance send -ttl 300000 -headers [list expires 150000] "/queue/exampleQueue" "message" -> Expiration Time 300 seconds from now
		
! it is important that the Broker and tStomp run on the same timezone or else the difference is calculated !
		
A ttl of 0 will result in an Expiration Time of 0, meaning it will not expire.
	
	tStomp_instance send -headers [list ttl 0] "/queue/exampleQueue" "message" -> Expiration Time 0, the message will not expire
	tStomp_instance send -headers [list expires 0] "/queue/exampleQueue" "message" -> Expiration Time 0, the message will not expire
	tStomp_instance send -ttl 0 "/queue/exampleQueue" "message" -> Expiration Time 0, the message will not expire
	
Subscribing to a queue will enable to receive messages which are sent to that queue. Every time a message is received the callBackScript is called.
	
	tStomp_instance subscribe "/queue/subscribeQueue" {puts "message received"}
		
Received messages are handled by the handleInput method, which reads line after line. At the end of file the connection is closed until another message comes up.
	
Every line is given to the handleLine method.
A message consists of three parts: star, header, messagebody.
Start is the type of the message: 
	
	CONNECTED: to confirm if a connection is established
	MESSAGE: a message with a either a text or an application
	ERROR: an error to be thrown

The messagebody is handled different depending on the type.
	
	CONNECTED: callBackScript is called
	ERROR: the error is thrown
	MESSAGE: on_receive method called
	
The on_receive method executes the callBackScripts given by the subscribers with the arguments sent with the message.
	
The unsubscribe method unsubscribes from the given queue and erases the correlating callBackScript.
	
	tStomp_instance unsubscribe "/queue/exampleQueue"
	
To disconnect the disconnect method may be called. It is possible to force the disconnect with the parameter force. If force is set the notConnected error is ignored.
	
	tStomp_instance disconnect -> force = 0
	tStomp_instance disconnect 1 -> force = 1
		
## First Heart Beat Implementation
A first step towards Stomp 1.2 compatibility is the implementation of heart beat messages. With tStomp is possible to ask the server for sending heart beats. About all heartBeatExpected ms the script heartBeatScript will be called. If the connection get's lost, a reconnection is triggered. 

	tStomp_instance connect {puts "CONNECTED"} -heartBeatScript {puts "heart beat isConnected=[tStomp_instance getIsConnected]"}  -heartBeatExpected 1000


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
			Class called with the ipaddress and port and values are initialised in the constructor. stompUrl should have the format: stomp://username:password@host:port
		destructor {}
			Called when objects of the class are deleted
		public connect {onConnectScript}
			connects to given host and port. onConnectScript is called after connection is confirmed
		private connectCallback {}
			After the re-/connect succeeded, try to restore the existing subscribtions
		public disconnect {force 0}
			disconnects from server
		private execute {destination script {messageNvList{}}}
			executes a script, e.g. a script defined for a destination or the callback script
		public handleInput {}
			Called from fileevent - reads one line. if eof it closes the connection and reconnects afterwards. 
		private handleLine {line}
			Method called whenever input arrives on a connection. Server Responses for the commands
			splits message in command, headers and messagebody (e.g. command: MESSAGE header: server:ActiveMQ/version-name version:1.1 session:ID:host-uniqueid messagebody: testMessage)
			calls methods depending on command (e.g. onConnectScript if CONNECTED, on_receive if MESSAGE)
		private on_receive {}
			invoked when the server response frame is MESSAGE
			converts messagebody from utf-8 and calls execute with the encoded message
		private reconnect {}
			In case of EOF (End of File -> losing connection) try to reconnect
			The reconnect subscribes all queues and topics again.
		public send {args}
			The SEND command sends a message to a destination in the messaging system.
			It has one required header, destination, which indicates where to send the message.
			The body of the SEND command is the message to be sent.			
			given options may be correaltionId, replyTo, persistent (false by default), ttl, headers. all other options must be given in headers
			if an option and a header exists, the header will be overwritten by the option
		public subscribe {destName callbackscript}
			Command is used to register to listen to a given destination. On every received message callbackscript will be called
		private _subscribe {destName}
			subscribe method only needed when reconnecting
		public testConnectionFailure
			Method to simulate a connection failure (internal)
		public testhandleLine
			Method to test the handleLine method (internal)
		public handleHeartBeatFail
			internal method called by timeout script if there is no heartbeat within min(3*heartBeatExpected,10000) ms.
			This method executes heartBeatScript and tries a reconnect. 
		public unsubscribe {destName}
			unsubscribes the given destination. correlating callbackscript will be removed
		public getDestinationId {destination}
			returns the id of the given destination
		public getStompVersion {}
			returns the current stomp version
		public getIsConnected {}
			returns if the tStomp is connected
		public setWriteSocketFile {status}
			set to enable logging. tStomp log is written in tStomp.log . if nothing is set logging is disabled
```
Integration Tests are found in tStomp.tcl.test .
		

# History
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

