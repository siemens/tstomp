# tStomp.tcl - This is a Stomp Implementation for TCL
# The Stomp Protocol Specification can be found at http://stomp.github.com/stomp-specification-1.1.html
#
# Copyright (c) 2011, SIEMENS AG, see file "LICENSE".
# Authors: Derk Muenchhausen, Sravanthi Anumakonda, Franziska Haunolder, Christian Ringhut, Jan Schimanski, Gaspare Mellino, Alexander Vetter, Fabian Kaiser
#
# See the file "LICENSE" for information on usage and redistribution
# of this file and for a DISCLAIMER OF ALL WARRANTIES.
# 
# Possible error codes are:
# -alreadyConnected
# -notConnected
# -wrongArgs
# -notSuscribedToGivenDestination

package provide tStomp 0.10

package require Itcl
package require struct::set
package require cmdline
package require md5

namespace import -force ::itcl::*

# catch - Evaluate script and trap exceptional returns
catch {delete class tStomp}

class tStomp {
	# array: holds the Destination names the client has subscribed to; the value contains the callback script
	variable scriptsOfSubscribedDestinations

	# holds the ip address
	variable host "unknown"

	# the port we need to connect (e.g. ActiveMQ Message Broker uses port 61613 for Stomp protocol)
	variable port 0
	
	# holds the channel identifier once the channel is opened
	variable connection_to_server

	# holds the username for authentication
	variable username "anonymous"

	# holds the password for authentication
	variable password "secret"
	
	# holds the available brokers
	variable listOfBrokers

	# index for actual broker
	variable brokerIndex 0

	# Boolean value for checking Connection is established or not
	variable isConnected 0

	# script called on the response of "CONNECT" Command
	variable onConnectScript

	# status indicates actual reading position
	variable readStatus

	# which message command is actual read
	variable readCommand

	# array of all params names and values of the actual read message
	variable params

	# handleInput calledCounter
	variable calledCounter 0 

	# stomp protocol version e.g. 1.0, 1.1
	variable stompVersion ""

	# test mode
	variable testMode 0

	# server name and version e.g. ActiveMQ/5.9.0
	variable serverInfo

	# additional connection headers
	variable additionalHeaders

	# how often is a heart beat from server side expected
	variable heartBeatExpected 0

	# script to be called after receiving a server heart beat or an heart beat timeout
	variable heartBeatScript ""

	# for heart beat timeout handling
	variable heartBeatAfterId ""

	# min heartbeat timeout
	variable minHeartBeatTime 10000

	# supervisionTime: after a connection, no reconnect is allowed within this period (in sec)
	variable supervisionTime 180

	# timestamp of last connection
	variable supervisionTimeStamp 0

	variable executionTimestampArray

	# Class called with the ipaddress and port and values are initialised in the constructor
	constructor {stompUrl} {} {
		# failover information will be ignored. We assume always a failover.
		set parsed [parseStompUrl $stompUrl]

		# only one broker supported right now
		set listOfBrokers [lindex $parsed 1]

		
		set isConnected  0
		
		set readStatus start
	}

	# Called when objects of the class are deleted
	destructor {
		disconnect 1
	}
	
	# Sends CONNECT frame
	# 
	# @param connectScript callback script for receiving CONNECTED message
	# @param additionalHeaders additional headers; name-value list
	public method connect {connectScript args} {
		
		set options {
			{heartBeatScript.arg "" "'script to be called after receifing heartBeat'"}
			{heartBeatExpected.arg 0 "'heart beat expected every <heartBeatExpected> ms'"}
			{reconnect.arg 0 "'reconnection 0|1 - use previous parameters'"}
			{supervisionTime.arg 180 "'after a connection, no reconnect is allowed within <supervisionTime> (in sec)'"}
		}
	
		array set option [cmdline::getKnownOptions args $options]
	
		set supervisionTime	$option(supervisionTime)

		if {!$option(reconnect)} {
			switch -exact [llength $args] {
				0 {set additionalHeaders ""}
				1 {set additionalHeaders [lindex $args 0]}
				default {
					error [cmdline::usage $options] "connectScript ?additionalHeaders?"
				}
			}
			set heartBeatExpected $option(heartBeatExpected)
			set heartBeatScript $option(heartBeatScript)
		}
		
		if {$isConnected} {
			error alreadyConnected
		}
			
		if {[namespace exists ::tStompCallbacks-$this]} {
			namespace delete ::tStompCallbacks-$this
		}
		namespace eval ::tStompCallbacks-$this {}
		
		set onConnectScript $connectScript
		
		set errorList [list]
		for {set i 0} {$i<[llength $listOfBrokers]} {incr i} {
			set r [catchedConnectNext]
			if {$r != ""} {
				lappend errorList $r
			} else {
				break
			}
		}
		
		if {$i >= [llength $listOfBrokers]} {
			error "connection to '$listOfBrokers' not possible. The collected errors are: '$errorList'"
		}
		 
		debug "socket to server $host:$port sucessfully opened" INFO
	}
	
	# return empty string on success or error text on error
	private method catchedConnectNext {} {
		
		set actualBroker [lindex $listOfBrokers $brokerIndex]
		
		set host [lindex $actualBroker 0]
		set port [lindex $actualBroker 1]
		
		set username [lindex $actualBroker 2]
		set password [lindex $actualBroker 3]
		
		set readStatus start
		
		set r [catch {
			
			# This command opens a network socket and returns a channel identifier
			set connection_to_server [socket $host $port]
			
			debug "connect to server $host:$port with $username" FINE
			
			# To do I/O operations on the channel in non blocking mode
			fconfigure $connection_to_server -blocking 0
			
			# No end-of-line translations are performed
			fconfigure $connection_to_server -translation {auto binary}
	
			if {[expr [llength $additionalHeaders] % 2] != 0} {
				error "param additionalHeaders must be a name-value list"
			}
	
			#############################################
			# Stomp Protocol format for CONNECT Command #
			#-------------------------------------------#
			#  CONNECT                                  #
			#  login: <username>                        #
			#  passcode:<passcode>                      #
			#                                           #
			#  ^@ ASCII null character.                 #
			#############################################
			puts $connection_to_server "CONNECT"
			puts $connection_to_server "heart-beat:0,$heartBeatExpected"
			puts $connection_to_server "accept-version:1.0,1.1,1.2"
			puts $connection_to_server "host:$host"
	
			if {[string length $username] > 0 && [string length $password] > 0} {
				puts $connection_to_server "login:$username"
				puts $connection_to_server "passcode:$password"
			}
	
			foreach {name value} $additionalHeaders {
				# check for headers already sent
				switch -- "$name" {
					"host" - "login" - "passcode" - "heart-beat" {
						error "host, login, passcode, heart-beat are not allowed as additional headers"
					}
				}
	
				puts $connection_to_server "${name}:${value}"
			}
	
			puts $connection_to_server ""
			puts $connection_to_server "\0"
			
			fileevent $connection_to_server readable [code $this handleInput]
			
			flush $connection_to_server	
		} err]
		set brokerIndex [expr ($brokerIndex + 1)%[llength $listOfBrokers]]			
		if {$r} {
			debug "connect error $err" INFO
			return $err
		}
		
		return ""
	}

	private method closeAndReconnect {} {
		debug "closeAndReconnect" WARNING

		catch {fileevent $connection_to_server readable ""}
		catch {close $connection_to_server}

		set isConnected 0

		if {$heartBeatExpected} {
			# call heart beat callback with isConnected=0
			executeLeastFrequently $heartBeatExpected handleHeartBeat $heartBeatScript [list] $isConnected $host $port
		}

		# switch of heartbeat until connection is reestublished
		after cancel $heartBeatAfterId

		# be careful when using multiple connections, the following construct will block all of them
		after 5000
		while 1 {
			if {[catch {reconnect}] == 0} {
				break
			}
			after 10000
		}

		if {$heartBeatExpected} {
			# call heart beat callback probably with isConnected=1
			executeLeastFrequently $heartBeatExpected handleHeartBeat $heartBeatScript [list] $isConnected $host $port
		}
	}
	
	# In case of EOF (End of File -> losing connection) try to reconnect
	#		The reconnect subscribes all queues and topics again.
	private method reconnect {} {
		debug "trying to reconnect..." INFO
		if {[catch {connect "" -reconnect 1} err] == 1} {
			debug "trying to reconnect: $err" INFO
			error "trying to reconnect: $err"
		}
	}
	
	# After the re-/connect succeeded, try to restore the existing subscriptions
	private method connectCallback {} { 
		debug "connection re-/established" INFO
	
		if {[array size scriptsOfSubscribedDestinations] != 0} {
			foreach {destname} [array names scriptsOfSubscribedDestinations] {
				_subscribe "$destname" {}

				debug "Re-subscribed to $destname" INFO
			}
		}

		# now time to switch heart beat on - but slowly we do not want continous reconnection 
		if {$heartBeatExpected} {
			set supervisionTimeStamp [clock seconds]
			recreateAfterScriptForHeartBeatFail 
		}
	}
	
	# Called from fileevent - reads one line
	public method handleInput {} {
		if {[eof $connection_to_server]} {
			debug "end of file" WARNING
			closeAndReconnect
		}

		incr calledCounter
		# debug "handleInput called: $calledCounter" FINEST
		gets $connection_to_server line

		handleLine $line
	}

	public method handleHeartBeatTimeout {} {	
		if {[expr [clock seconds] - $supervisionTimeStamp] > $supervisionTime} {
			debug "handleHeartBeatTimeout" WARNING
			closeAndReconnect
		} else {
			debug "handleHeartBeatTimeout supervsion: reconnect ignored" WARNING
		}
	}

	private method recreateAfterScriptForHeartBeatFail {} {
		set timeInMs [expr $heartBeatExpected*5<$minHeartBeatTime?$minHeartBeatTime:$heartBeatExpected*5]
		# debug "recreateAfterScriptForHeartBeatFail called $timeInMs" INFO
		after cancel $heartBeatAfterId
		set heartBeatAfterId [after $timeInMs "$this handleHeartBeatTimeout"] 
	}

	private method handleHeartBeat {} {
		# debug "handleHeartBeat [getIsConnected] $heartBeatExpected" INFO
			
		# handling a positive connection heart beat...
		if {$heartBeatExpected} {
			recreateAfterScriptForHeartBeatFail
			# positive heart beat - check it with isConnected
			executeLeastFrequently $heartBeatExpected handleHeartBeat $heartBeatScript [list] $isConnected $host $port
		}
	}

	#Method called whenever input arrives on a connection. Server Responses for the commands
	#		splits message in command, headers and messagebody (e.g. command: MESSAGE header: server:ActiveMQ/version-name version:1.1 session:ID:host-uniqueid messagebody: testMessage)
	#		calls methods depending on command (e.g. onConnectScript if CONNECTED, on_receive if MESSAGE)
	private method handleLine {line} {
		# debug $readStatus FINEST
		# debug "readline '$line'" FINEST
		set endOfMessage 0
		if {[regsub -all -- {\x00} $line "" line]} {
			set endOfMessage 1
		}

		switch -exact $readStatus {
			start {
				if {[string length $line]>0} {
					set readCommand $line
					set readStatus header
					# debug "handleLine: Stomp: $line" FINE
				}
				if {$isConnected} {
					# heart beat must not be called during connection setup because CONNECT might not been called yet
					handleHeartBeat
				}
			}
			header {
				if {[string length $line]>0} {
					# debug "handleLine: StompHeader: $line" FINE

					# because of activemq header encoding we need to turn "\c" (0x63) into ":"
					set line [string map {"\\\x63" :} $line]

                    regexp {^(.*?):(.*)$} $line all varName value

					set params($varName) $value
				} else {
					# debug "handleLine: StompHeaderEND: $line" FINE
					set readStatus messagebody
				}
			}
			messagebody {
				switch -exact -- $readCommand {
					CONNECTED {
					}
					MESSAGE - ERROR {
						append params(messagebody) $line

						if {!$endOfMessage} {
							# we don't know if it's the last line but we append newline anyway
							append params(messagebody) "\n"
						}
					}
					RECEIPT {
						debug "Handling RECEIPT messages -> not implemented yet"
					}
					default {
						debug "default case -> Server message $readCommand not known!"
					}
				}
			}
			end {
				debug "handleLine: end case -> not implemented yet"
			}
			default {
				debug "handleLine: default case -> not implemented yet"
			}
		}

		if {$endOfMessage} {
			# debug "handleInput: messageEnd" FINEST
			switch -exact $readCommand {
				CONNECTED {
					set isConnected 1

					if {[info exists params(version)]} {
						set stompVersion $params(version)
						debug "Stomp version: $stompVersion" FINE
					}

					if {[info exists params(server)]} {
						set serverInfo $params(server)
						debug "Server information: $serverInfo" FINE
					}

					# internal connect callback
					connectCallback

					# external connect callback
					execute connect $onConnectScript [list] $isConnected $host $port
				}
				MESSAGE {
					on_receive
				}
				ERROR {
					if {[info exists params(messagebody)]} {
						debug "handleInput: Got Error: $params(messagebody)" ERROR
					}
				}
				RECEIPT {
					debug "handleInput: RECEIPT messages -> not implemented yet"
				}
				default {
					debug "handleInput: default case -> Server message $readCommand not known!"
				}
			}
		
			set readStatus start

			if {!$testMode} {
				array unset params
			}
		}
	}

	# invoked when the server response frame is MESSAGE
	#		converts messagebody from utf-8 and calls execute with the encoded message
	private method on_receive {} {
		if {[info exists params(messagebody)]} {
			set params(messagebody) [encoding convertfrom utf-8 $params(messagebody)]
		}

		if {![info exists params(destination)]} {
			debug "destination is empty" SEVERE
			return
		}
		set destination $params(destination)
		if {![info exists scriptsOfSubscribedDestinations($destination)]} {
			debug "scriptsOfSubscribedDestinations($destination) does not exist" SEVERE
			return
		}
	
		execute $destination $scriptsOfSubscribedDestinations($destination) [array get params] $isConnected $host $port
	}
	
	# executes a script, e.g. a script defined for a destination or the callback script. The local variable $messageNvList $isConnected $host $port are available within the script.
	private method execute {name script messageNvList isConnected host port} {
		debug "execute name=$name script='$script' messageNvList='$messageNvList' isConnected=$isConnected host=$host port=$port" FINEST
		#  if a global execute_thread command is available, use it
		if [llength [info command execute_thread]] {
			execute_thread $script $messageNvList $isConnected $host $port
		} else {
			if {![llength [info commands ::tStompCallbacks-${this}::$name]]} {
				proc ::tStompCallbacks-${this}::$name {messageNvList isConnected host port} $script
			}
			::tStompCallbacks-${this}::$name $messageNvList $isConnected $host $port
		}
	}

	private method executeLeastFrequently {executionTimeFrame name script messageNvList isConnected host port} {
		set now [clock clicks -milliseconds]
		if {[info exists executionTimestampArray($name)]} {
			set lastExecution [lindex $executionTimestampArray($name) 0]
			set lastConnected [lindex $executionTimestampArray($name) 1]
			# a heartbeat can only be ignored, if there is no isConnected change this the last call
			if {$lastConnected == $isConnected} {
				if {[expr $now-$lastExecution] < $executionTimeFrame} {
					debug "$name ignored for the next [expr $executionTimeFrame-$now+$lastExecution]" FINEST
					return
				}
			}
		}
		set executionTimestampArray($name) [list $now $isConnected]
		execute $name $script $messageNvList $isConnected $host $port
	}

	public method testConnectionFailure {} {
		close $connection_to_server
	}

	# only for testing the handleLine Method
	public method testHandleLine {line} {
		set endOfMessage 0
		if {[regsub -all \x00 $line "" temp]} {
			set endOfMessage 1
		}

		set testMode 1
		
		handleLine $line
		set result [list [array get params] [list $readCommand] [list $readStatus]]
		
		set testMode 0

		if {$endOfMessage} {
			array unset params
		}

		return $result
	}

	# The SEND command sends a message to a destination in the messaging system.
	# It has one required header, destination, which indicates where to send the message.
	# The body of the SEND command is the message to be sent.
	#
	# send -replyTo /queue/FooBar -headers {foo 1 bar 2} /queue/Hello.World {this is a payload}
	# @param dest destination name e.g. /queue/test
	# @param msg message body
	public method send {args} {
		# debug "send with $args" FINEST
		
		if {$isConnected == 0} {
			error notConnected
		}
	
		# all options can be given as headers or options
		# if an option and a header exists, the header will be overwritten by the option
		set options {
			{correlationId.arg ""}
			{replyTo.arg ""}
			{persistent.arg ""}
			{ttl.arg ""}
			{headers.arg {}}
		}
	
		array set option [cmdline::getKnownOptions args $options]
		
		if {[llength $args] != 2} {
			error [cmdline::usage $options]
		} else {
			foreach {dest msg} $args {break}
		}

		# debug "send $msg to destination $dest" FINE
		debug "send to destination $dest" FINE
		
		# option headers
		array set headers $option(headers)

		# header ttl is overwritten by header expires
		# header expires is overwritten by option ttl
		if {[info exists headers(ttl)] && $headers(ttl) != ""} {
			if {![info exists headers(expires)]} {
				set headers(expires) [format %.0f [expr $headers(ttl) == 0 ? 0 : ([clock seconds] * 1000.0 + $headers(ttl))]]
			} else {
				debug "header expires already set, header ttl ignored" WARNING
			}
		}

		# special options
		if {$option(ttl) != ""} {
			if {[info exists headers(expires)]} {
				debug "existing header expires was overwritten by option ttl" WARNING
			}

			set headers(expires) [format %.0f [expr $option(ttl) == 0 ? 0 : ([clock seconds] * 1000.0 + $option(ttl))]]
		}
		
		set specialOptionMap {
			correlationId correlation-id
			replyTo reply-to
			persistent persistent
		}

		foreach {optionName headerName} $specialOptionMap {
			if {$option(${optionName}) != ""} {
				if {[info exists headers(${headerName})] && $headers(${headerName}) != $option(${optionName})} {
					debug "existing header ${headerName} was overwritten by option ${optionName}" WARNING
				}

				set headers(${headerName}) $option(${optionName})
			}
		}

		catch {unset headers(ttl)}

		puts $connection_to_server "SEND"
		puts $connection_to_server "destination:$dest"
		
		foreach name [array names headers] {
			puts $connection_to_server "$name:$headers(${name})"
		}

		array unset headers
		
		puts $connection_to_server ""
		puts $connection_to_server "[encoding convertto utf-8 $msg]\0"
		flush $connection_to_server

		return 1
	}

	# Command is used to register to listen to a given destination.
	# Can be called before connect.
	# 
	# subscribe /queue/foo {puts "We got a message on foo! $messageNvList"}
	# 
	# @param destination name of destination e.g. /queue/foo
	# @param callbackScript script called on receiving message for destination
	# @param additionalHeaders 
	public method subscribe {destination callbackScript {additionalHeaders {}}} {
		if {[info exists scriptsOfSubscribedDestinations($destination)]} {
			set scriptsOfSubscribedDestinations($destination) $callbackScript

			if {[llength [info commands ::tStompCallbacks-${this}::$destination]]} {
				rename ::tStompCallbacks-${this}::$destination ""
			}
		} else {
			# will be done on connect
			if {$isConnected == 1} {
				_subscribe $destination $additionalHeaders
			}

			set scriptsOfSubscribedDestinations($destination) $callbackScript
		}

		debug "Subscribed to destination $destination" INFO

		return 1
	}

	# The internal subscribe method we need in case of reconnect
	# 
	# @param destination name of destination e.g. /queue/foo
	private method _subscribe {destination additionalHeaders} {
		if {[expr [llength $additionalHeaders] % 2] != 0} {
			error "param additionalHeaders must be a name-value list"
		}

		puts $connection_to_server "SUBSCRIBE"
		if {$stompVersion != "1.0"} {
			puts $connection_to_server "id:[getDestinationId $destination]"
		}
		puts $connection_to_server "destination:$destination"

		foreach {name value} $additionalHeaders {
			# check for headers already sent
			switch -- "$name" {
				"id" - "destination" {
					error "id, destination are not allowed as additional headers"
				}
			}

			puts $connection_to_server "${name}:${value}"
		}

		puts $connection_to_server ""
		puts $connection_to_server "\0"

		flush $connection_to_server
	}

	# The unsubscribe command is used to remove an existing subscription - to no longer receive messages from that destination.
	# unsubscribe /queue/foo
	public method unsubscribe {destName {additionalHeaders {}}} {
		if {$isConnected == 0} {
			error notConnected
		}
		
		debug "Unsubscribe to destination $destName" INFO

		if {[info exists scriptsOfSubscribedDestinations($destName)]} {
			unset scriptsOfSubscribedDestinations($destName)

			if {[expr [llength $additionalHeaders] % 2] != 0} {
				error "param additionalHeaders must be a name-value list"
			}
		
			puts $connection_to_server "UNSUBSCRIBE"
			if {$stompVersion == "1.0"} {
				puts $connection_to_server "destination:$destName"
			} else {
				puts $connection_to_server "id:[getDestinationId $destName]"
			}

			foreach {name value} $additionalHeaders {
				# check for headers already sent
				switch -- "$name" {
					"id" - "destination" {
						error "id, destination are not allowed as additional headers"
					}
				}

				puts $connection_to_server "${name}:${value}"
			}

			puts $connection_to_server ""
			puts $connection_to_server "\0"
			flush $connection_to_server
			
			if {[llength [info commands ::tStompCallbacks-${this}::$destName]]} {
				rename ::tStompCallbacks-${this}::$destName ""
			}
		} else {
			debug "No subscription for $destName" WARNING
			error "No subscription for $destName"
		}

		return 1
	}
		
	# Disconnects and restores the variables
	public method disconnect {{force 0}} {
		after cancel $heartBeatAfterId
		if {$isConnected == 0} {
			if {$force == 0} {
				error notConnected
			}
		} else {
			puts $connection_to_server "DISCONNECT"
			puts $connection_to_server ""
			puts $connection_to_server "\0"
			flush $connection_to_server
		}

		if {[info exists connection_to_server]} {
			if {[catch {
				close $connection_to_server
			} err]} {
				debug "error during disconnect close: $err" INFO
			}
			unset connection_to_server
		}
		
		array unset scriptsOfSubscribedDestinations

		set isConnected 0

		return 1
	}

	public method getDestinationId {destination} {
		return [md5::md5 -hex $destination]
	}

	public method getStompVersion {} {
		return $stompVersion
	}
	
	public method getIsConnected {} {
		return $isConnected
	}

	# this method changes the value for heartbeatexpected, but be aware that the new value will get active not before a reconnection
	# main purpose for this method is testing
	public method setHeartBeatExpected {newHeartBeatExpected} {
		set heartBeatExpected $newHeartBeatExpected
	}

	# Overwrites the debug command. e.g. own log file for stomp functionality
	# tStomp::setDebugCmd {::debug $msg $level}
	# tStomp::setDebugCmd {trace $msg}
	proc setDebugCmd {script} {
		proc ::tStompDebug::debug {msg {level ""}} $script
	}

	proc debug {msg {level ""}} {
		::tStompDebug::debug $msg $level
	}
	
	proc parseStompUrl {stompUrl} {
		
		if ![set failover [regexp {failover:\((.*)\)} $stompUrl all brokerUrlList]] {
			set brokerUrlList $stompUrl
		}

		set brokerList [list]

		foreach brokerUrl [split $brokerUrlList ,] {
			regsub "stomp:(tcp:)?//" $brokerUrl "" brokerInfo
			
			set brokerInfo [split [split $brokerInfo ":"] "@"]

			if {[llength $brokerInfo] == 2} {
				set login [lindex $brokerInfo 0 0]
				set passcode [lindex $brokerInfo 0 1]
				
				set host [lindex $brokerInfo 1 0]
				set port [lindex $brokerInfo 1 1]
			} elseif {[llength $brokerInfo] == 1} {
				set login ""
				set passcode ""
				
				set host [lindex $brokerInfo 0 0]
				set port [lindex $brokerInfo 0 1]
			} else {
				error "wrong format"
			}
			
			lappend brokerList [list $host $port $login $passcode]
		}

		return [list $failover $brokerList];
	}
}

namespace eval tStompDebug {
	proc debug {msg {level ""}} {
		puts "STOMPLog: $msg"
	}
}

