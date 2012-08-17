# tStomp.tcl - This is a Stomp Implementation for TCL
# The Stomp Protocol Specification can be found at http://stomp.github.com/stomp-specification-1.1.html
#
# Copyright (c) 2011, SIEMENS AG, see file "LICENSE".
# Authors: Derk Muenchhausen, Sravanthi Anumakonda, Franziska Haunolder, Christian Ringhut, Jan Schimanski, Gaspare Mellino
#
# See the file "LICENSE" for information on usage and redistribution
# of this file and for a DISCLAIMER OF ALL WARRANTIES.
# 
# Possible error codes are:
# -alreadyConnected
# -notConnected
# -wrongArgs
# -notSuscribedToGivenDestination
#

package provide tStomp 0.4
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

	# Class called with the ipaddress and port and values are initialised in the constructor
	constructor {ip p} {} {
		set host $ip
		set port $p
		set isConnected  0
		set readStatus start
	}

	# Called when objects of the class are deleted
	destructor {
		disconnect 1
	}
	
	public method connect {_onConnectScript} {
		if {$isConnected} {
			error alreadyConnected
		}
				
		if {[namespace exists ::tStompCallbacks-$this]} {
			namespace delete ::tStompCallbacks-$this
		}
		namespace eval ::tStompCallbacks-$this {}
		
		set readStatus start
		set onConnectScript $_onConnectScript
		
		# This command opens a network socket and returns a channel identifier
		debug "connection_to_server socket $host $port"
		set connection_to_server [socket $host $port]
		# To do I/O operations on the channel in non blocking mode
		fconfigure $connection_to_server -blocking 0
		# No end-of-line translations are performed
		fconfigure $connection_to_server -translation {auto binary}
#		fconfigure $connection_to_server -translation {auto lf} -encoding utf-8

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
		puts $connection_to_server ""
		puts $connection_to_server "\0"
		
		fileevent  $connection_to_server readable [code $this handleInput]
		
		flush $connection_to_server	
	}
	
	# In case of EOF (losing connection) try to reconnect
	private method reconnect {} {
		debug "trying to reconnect..."
		if {[catch {connect  ""} err] == 1} {
			error $err
		}
	}
	
	# After the re-/connect succeeded, try to restore the existing subscribtions
	private method connectCallback {} { 
		debug "connection re-/established"
		
		if {[array size scriptsOfSubscribedDestinations] != 0} {
			foreach {destname} [array names scriptsOfSubscribedDestinations] {
				_subscribe "$destname"
				debug "destination: '$destname' re-subscribed"
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
		if {[regsub -all \x00 $line "" line]} {
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
					set splitHeader [regsub : $line " " ]
					set varName [lindex $splitHeader 0]
					set params($varName) [lindex $splitHeader 1]
				} else {
					debug "handleLine: StompHeaderEND: $line" FINE
					set readStatus messagebody
				}
			}
			messagebody {
				switch -exact $readCommand {
					CONNECTED {
					}
					MESSAGE {
						append params(messagebody) $line
					}
					ERROR {
						if {[info exists params(messagebody)]} {
							debug "Got Error: $params(messagebody)"
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
						debug "stompVersion: $stompVersion" FINEST
					}
					connectCallback
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
			unset params
		}
	}

	# invoked when the server response frame is MESSAGE
	private method on_receive {} {

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
			debug "execute_thread $script $messageNvList"
			execute_thread $script $messageNvList
		} else {
			debug "uplevel $script $messageNvList"
			if {![llength [info commands ::tStompCallbacks-${this}::$destination]]} {
				proc ::tStompCallbacks-${this}::$destination {messageNvList} $script
			}
			::tStompCallbacks-${this}::$destination $messageNvList
		}
	}

	# only for testing the handleLine Method
	public method testHandleLine {line} {
		handleLine $line
		return [list [array get params] [list $readCommand] [list $readStatus]]
	}

	# The SEND command sends a message to a destination in the messaging system.
	# It has one required header, destination, which indicates where to send the message.
	# The body of the SEND command is the message to be sent.
	#
	# send -replyTo /queue/FooBar -headers {foo 1 bar 2} /queue/Hello.World
	public method send {args} {
		debug "send $args" FINEST
		debug "args.length [llength $args]" FINEST
		
		if {$isConnected == 0} {
			error notConnected
		}
	
		set options [list\
			{correlationId.arg ""}\
			{replyTo.arg ""}\
			{headers.arg {}}\
		]
	
		array set option [cmdline::getKnownOptions args $options]
	
		debug "args.length [llength $args]" FINEST
		
		if {[llength $args] != 2} {
			#error [cmdline::usage ?-correlationId <correlationId>? ?-replyTo <replyTo>? ?-headers [list <name> <value> ...]? dest msg]
			error wrongArgs
		} else {
			foreach {dest msg} $args {break}
		}

		debug "send args> $args - dest> $dest - msg> $msg"
	
		puts $connection_to_server "SEND"
		puts $connection_to_server "destination:$dest"
		puts $connection_to_server "persistent:true"


		
		if {$option(correlationId) != ""} {
			puts $connection_to_server "correlation-id:$option(correlationId)"
		}
		if {$option(replyTo) != ""} {
			puts $connection_to_server "reply-to:$option(replyTo)"
		}
		if {$option(headers) != ""} {
			foreach {n v} $option(headers) {
				puts $connection_to_server "$n:$v"
			}
		}
		puts $connection_to_server ""
		puts $connection_to_server "[encoding convertto utf-8 $msg]"
		puts $connection_to_server "\0"
		flush $connection_to_server

		return 1
	}

	# Command is used to register to listen to a given destination.
	# subscribe /queue/foo callbackscript
	public method subscribe {destName callbackscript} {

		if {[info exists scriptsOfSubscribedDestinations($destName)]} {
			set scriptsOfSubscribedDestinations($destName) $callbackscript
			if {[llength [info commands ::tStompCallbacks-${this}::$destName]]} {
				rename ::tStompCallbacks-${this}::$destName ""
			}

		} else {
			# will be done on connect
			if {$isConnected == 1} {
				_subscribe $destName
			}
			set scriptsOfSubscribedDestinations($destName) $callbackscript
		}
		debug "Destination $destName subscribed"
		return 1
	}

	# The internal subscribe method we need in case of reconnect
	private method _subscribe {destName} {
		puts $connection_to_server "SUBSCRIBE"
		if {$stompVersion != "1.0"} {
			puts $connection_to_server "id:[getDestinationId $destName]"
		}
		puts $connection_to_server "destination:$destName"
		puts $connection_to_server ""
		puts $connection_to_server "\0"
		flush $connection_to_server
	}

	# The unsubscribe command is used to remove an existing subscription - to no longer receive messages from that destination.
	# unsubscribe /queue/foo
	public method unsubscribe {destName} {
		if {$isConnected == 0} {
			error notConnected
		}
		
		debug "in the unsubscribe method - '$destName'"
		debug "array [array  get scriptsOfSubscribedDestinations]"
		if {[info exists scriptsOfSubscribedDestinations($destName)]} {
			unset scriptsOfSubscribedDestinations($destName)
			puts $connection_to_server "UNSUBSCRIBE"
			if {$stompVersion == "1.0"} {
					puts $connection_to_server "destination:$destName"
			} else {
						   puts $connection_to_server "id:[getDestinationId $destName]"
			}
			puts $connection_to_server ""
			puts $connection_to_server "\0"
			flush $connection_to_server
			
			if {[llength [info commands ::tStompCallbacks-${this}::$destName]]} {
				rename ::tStompCallbacks-${this}::$destName ""
			}
		} else {
			debug "scriptsOfSubscribedDestinations($destName) not exists"
			error notSuscribedToGivenDestination
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
}

namespace eval tStompDebug {
	proc debug {msg {level ""}} {
		puts "STOMPLog: $msg"
	}
}

