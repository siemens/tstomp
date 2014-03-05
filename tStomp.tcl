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

package provide tStomp 0.5

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
	variable host

	# the port we need to connect (e.g. ActiveMQ Message Broker uses port 61613 for Stomp protocol)
	variable port

	# holds the channel identifier once the channel is opened
	variable connection_to_server

	# holds the username for authentication
	variable username

	# holds the password for authentication
	variable password

	# Boolean value for checking Connection is established or not
	variable isConnected

	# script called on the response of "CONNECT" Command
	variable onConnectScript

	# writing every content of socket in a Logfile
	variable writeSocketFile 0

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

	# failover flag (not in use yet)
	variable failover 0

	# server name and version e.g. ActiveMQ/5.9.0
	variable serverInfo

	# Class called with the ipaddress and port and values are initialised in the constructor
	constructor {stompUrl} {} {
		set parsed [parseStompUrl $stompUrl]
		
		set failover [lindex $parsed 0 0]

		# only one broker supported right now
		set broker [lindex $parsed 1 0]

		set host [lindex $broker 0]
		set port [lindex $broker 1]
		
		set username [lindex $broker 2]
		set password [lindex $broker 3]
		
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
	public method connect {connectScript {additionalHeaders {}}} {
		if {$isConnected} {
			error alreadyConnected
		}
			
		if {[namespace exists ::tStompCallbacks-$this]} {
			namespace delete ::tStompCallbacks-$this
		}
		namespace eval ::tStompCallbacks-$this {}
		
		set readStatus start
		set onConnectScript $connectScript
		
		# This command opens a network socket and returns a channel identifier
		set connection_to_server [socket $host $port]
		
		debug "connect to server $host:$port with $username"
		
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
		puts $connection_to_server "accept-version:1.0,1.1"
		puts $connection_to_server "host:$host"

		if {[string length $username] > 0 && [string length $password] > 0} {
			puts $connection_to_server "login:$username"
			puts $connection_to_server "passcode:$password"
		}

		# as for now tStomp doesn't support heart-beat
		puts $connection_to_server "heart-beat:0,0"
		
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

		debug "socket connect to server $host:$port succeeded"
	}
	
	# In case of EOF (losing connection) try to reconnect
	private method reconnect {} {
		debug "trying to reconnect..."
		if {[catch {connect ""} err] == 1} {
			error "trying to reconnect: $err"
		}
	}
	
	# After the re-/connect succeeded, try to restore the existing subscriptions
	private method connectCallback {} { 
		debug "connection re-/established"
		
		if {[array size scriptsOfSubscribedDestinations] != 0} {
			foreach {destname} [array names scriptsOfSubscribedDestinations] {
				_subscribe "$destname" {}

				debug "Re-subscribed to $destname"
			}
		}
	}
	
	# Called from fileevent - reads one line
	public method handleInput {} {
		if {[eof $connection_to_server]} {
			debug "end of file"
			catch {close $connection_to_server}
			set isConnected 0
			
			# be careful when using multiple connections, the following construct will block all of them
			after 5000
			while 1 {
				if {[catch {reconnect}] == 0} {
					break
				}
				after 10000
			}
		}

		incr calledCounter
		debug "handleInput called: $calledCounter" FINEST
		gets $connection_to_server line

		if {$writeSocketFile == 1} {
			writeFile "$line"
		}

		handleLine $line
	}

	# Method called whenever input arrives on a connection. Server Responses for the commands
	private method handleLine {line} {

		set endOfMessage 0
		if {[regsub -all -- {\x00} $line "" line]} {
			set endOfMessage 1
		}

		switch -exact $readStatus {
			start {
				if {[string length $line]>0} {
					set readCommand $line
					set readStatus header
					debug "handleLine: Stomp: $line" FINE
				}
			}
			header {
				if {[string length $line]>0} {
					debug "handleLine: StompHeader: $line" FINE

					# because of activemq header encoding we need to turn "\c" (0x63) into ":"
					set line [string map {"\\\x63" :} $line]

					set splitHeader [regsub -- ":" $line " "]
					set varName [lindex $splitHeader 0]
					set value [lindex $splitHeader 1]

					set params($varName) $value
				} else {
					debug "handleLine: StompHeaderEND: $line" FINE
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
			debug "handleInput: messageEnd" FINEST
			switch -exact $readCommand {
				CONNECTED {
					set isConnected 1

					if [info exists params(version)] {
						set stompVersion $params(version)
						debug "Stomp version: $stompVersion" FINEST
					}

					if [info exists params(server)] {
						set serverInfo $params(server)
						debug "Server information: $serverInfo" FINEST
					}

					# internal connect callback
					connectCallback

					# external connect callback
					execute connect $onConnectScript
				}
				MESSAGE {
					on_receive
				}
				ERROR {
					if {[info exists params(messagebody)]} {
						debug "handleInput: Got Error: $params(messagebody)"
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
	private method on_receive {} {
		if {[info exists params(messagebody)]} {
			set params(messagebody) [encoding convertfrom utf-8 $params(messagebody)]
		}

		if {![info exists params(destination)]} {
			debug "destination is empty"
			return
		}
		set destination $params(destination)
		if {![info exists scriptsOfSubscribedDestinations($destination)]} {
			debug "scriptsOfSubscribedDestinations($destination) does not exist"
			return
		}
	
		execute $destination $scriptsOfSubscribedDestinations($destination) [array get params]
	}
	
	# executes a script, e.g. a script defined for a destination or the callback script
	private method execute {destination script {messageNvList {}}} {
		debug "im stomp execute: $script ---- | ---- $messageNvList"
		
		#  if a global execute_thread command is available, use it
		if [llength [info command execute_thread]] {
			debug "execute_thread $script $messageNvList" FINE
			execute_thread $script $messageNvList
		} else {
			debug "uplevel $script $messageNvList" FINE
			if {![llength [info commands ::tStompCallbacks-${this}::$destination]]} {
				proc ::tStompCallbacks-${this}::$destination {messageNvList} $script
			}
			::tStompCallbacks-${this}::$destination $messageNvList
		}
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
	# send -replyTo /queue/FooBar -headers {foo 1 bar 2} /queue/Hello.World
	# @param dest destination name e.g. /queue/test
	# @param msg message body
	public method send {args} {
		debug "send with $args" FINEST
		
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

		debug "send $msg to destination $dest" FINE
	
		# option headers
		array set headers $option(headers)

		# header ttl is overwritten by header expires
		# header expires is overwritten by option ttl
		if {[info exists headers(ttl)] && $headers(ttl) != ""} {
			if {![info exists headers(expires)]} {
				set headers(expires) [format %.0f [expr $headers(ttl) == 0 ? 0 : ([clock seconds] * 1000.0 + $headers(ttl))]]
			} else {
				debug "header expires already set, header ttl ignored" WARN
			}
		}

		# special options
		if {$option(ttl) != ""} {
			if {[info exists headers(expires)]} {
				debug "existing header expires was overwritten by option ttl" WARN
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
					debug "existing header ${headerName} was overwritten by option ${optionName}" WARN
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

		debug "Subscribed to destination $destination"

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
		
		debug "Unsubscribe to destination $destName"

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
			debug "No subscription for $destName"
			error "No subscription for $destName"
		}

		return 1
	}
		
	# Disconnects and restores the variables
	public method disconnect {{force 0}} {
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

		if {[catch {
			close $connection_to_server
		} err]} {
			debug "disconnect close: $err"
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

	public method setWriteSocketFile {status} {
		set writeSocketFile $status
	}

	# Writes the hole socket input into a local file
	proc writeFile {text} {
		set fid [open tStomp.log a+]
		puts $fid $text
		close $fid
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
		# we parse for failover but we don't support it yet
		
		if ![set failover [regexp {failover:\((.*)\)} $stompUrl all brokerUrlList]] {
			set brokerUrlList $stompUrl
		}

		set brokerList [list]

		foreach brokerUrl [split $brokerUrlList ,] {
			regsub "stomp://" $brokerUrl "" brokerInfo
			
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