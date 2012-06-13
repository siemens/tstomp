# tStomp.tcl - This is a Stomp Implementation for TCL
# The Stomp Protocol Specification can be found at http://stomp.github.com/stomp-specification-1.1.html
#
# Copyright (c) 2011, SIEMENS AG, see file "LICENSE".
# Authors: Derk Muenchhausen, Sravanthi Anumakonda, Franziska Haunolder
#
# See the file "LICENSE" for information on usage and redistribution
# of this file and for a DISCLAIMER OF ALL WARRANTIES.
# 

package provide tStomp 1.0
package require Itcl
package require struct::set
package require cmdline
package require md5

namespace import -force ::itcl::*

#catch - Evaluate script and trap exceptional returns
catch {delete class tStomp}

class tStomp {
	# array: holds the Destination names the client has subscribed to; the value contains the callback script
	variable subscribedDestinations
	# output
	variable output ""
	# holds the ip address
	variable host
	# the port we need to connect(If ActiveMQ Message Broker is used it connects to 61613)
	variable port
	# holds the channel identifier once the channel is opened
	variable connection_to_server
	# Boolean value for checking Connection is established or not
	variable isConnected
	# Boolean value for checking if there is any error
	variable isError
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

	# class called with the ipaddress and port and values are initialised in the constructor
	constructor {ip p} {} {
		set host $ip
		set port $p
		set isConnected  0
		set isError 0
		set readStatus start
	}

	# called when objects of the class are deleted
	destructor {
		disconnect
	}

	public method connect { _onConnectScript } {
		#This command opens a network socket and returns a channel identifier
		#set connection_to_server [socket desw138x 61622]
		debug "connection_to_server socket $host $port"
		set connection_to_server [socket $host $port]
		#fconfigure - command sets and retrieves options for channels. format : fconfigure channelId
		#ChannelId identifies the channel for which to set or query an option
		#-blocking 0 -> To do I/O operations on the channel in non blocking mode
		fconfigure $connection_to_server -blocking 0
		#-auto binary -> No end-of-line translations are performed
		fconfigure $connection_to_server -translation {auto binary}
		#	Stomp Protocol format for CONNECT Command
		#Initially the client must open a socket using the Connect Command.
		#  CONNECT
		#  login: <username>
		#  passcode:<passcode>
		#
		#  ^@ ASCII null character.
		puts $connection_to_server "CONNECT"
		puts $connection_to_server "accept-version:1.0,1.1"
		puts $connection_to_server ""
		puts $connection_to_server "\0"


		set onConnectScript $_onConnectScript
		fileevent  $connection_to_server readable [list $this handleInput ]

		# Server responds with "CONNECTED" or "ERROR" frame
		flush $connection_to_server	
	}

	method handleInput {} {
		incr calledCounter
		debug "handleInput called: $calledCounter" FINEST
	
		# Delete the handler if the input was exhausted.
		if {[eof $connection_to_server]} {
			fileevent $connection_to_server readable {}
			close $connection_to_server
			return
		}

		gets $connection_to_server line

		if {$writeSocketFile == 1} {
			writeFile "$line"
		}

		handleLine $line

	}

	# Method called whenever input arrives on a connection. Server Responses for the commands
	method handleLine {line} {

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
					set splitHeader [regsub : $line " "]
					set varName [lindex $splitHeader 0]
					set varName [string map {- ""} $varName]
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

		# End of Message
		if {[regsub -all \x00 $line "" line] == 1} {
			debug "handleInput: messageEnd" FINEST
			switch -exact $readCommand {
				CONNECTED {
					set isConnected 1
					if [info exists params(version)] {
						set stompVersion $params(version)
						debug "stompVersion: $stompVersion" FINEST
					}
					execute $onConnectScript
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

	public method testHandleLine {line} {
		handleLine $line
		return [list [array get params] [list $readCommand] [list $readStatus]]
	}

	#The SEND command sends a message to a destination in the messaging system.
	#It has one required header, destination, which indicates where to send the message.
	#The body of the SEND command is the message to be sent.
	# SEND
	# destination:/queue/foo  or /topic/foohttp://www.tcp-ip-info.de/tcp_ip_und_internet/ascii.gif

	#hello queue foo  or  hello topic foo

	public method send {args} {
		debug "send $args" FINEST
		debug "args.length [llength $args]" FINEST
	
		if {$isConnected == 0} {
			return 0
		}
	
		set options [list\
			{correlationId.arg ""}\
			{replyTo.arg ""}\
			{out.arg ""}\
			{headers.arg {}}\
		]
	
		array set option [cmdline::getKnownOptions args $options]
	
		debug "args.length [llength $args]" FINEST
		
		if {[llength $args] != 2} {
			error [cmdline::usage $options " dest msg ?-correlationId <correlationId> ?-replyTo <replyTo>? ?-out <out>? "]
		} else {
			foreach {dest msg} $args {break}
		}

		debug "send args> $args - dest> $dest - msg> $msg"
	
		if {$option(out)==""} {
			debug "option(out)> $option(out)"
			#send $dest $msg $option(correlationId) stdout
			set out $connection_to_server
		} else {
			set out $option(out)
		}
		puts $out "SEND"
		puts $out "destination:$dest"
		puts $out "persistent:true"
		
		if {$option(correlationId) != ""} {
			puts $out "correlation-id:$option(correlationId)"
		}
		if {$option(replyTo) != ""} {
			puts $out "reply-to:$option(replyTo)"
		}
		if {$option(headers) != ""} {
			foreach {n v} $option(headers) {
				puts $out "$n:$v"
			}
		}
		
		puts $out ""
		puts $out "$msg [lrange [split $dest /] 1 end]"
		puts $out "\0"
		flush $out

		return 1

	}

	#The SUBSCRIBE command is used to register to listen to a given destination.
	#SUBSCRIBE
	# destination: /queue/foo
	# callbackscript

	public method subscribe {destName callbackscript} {
	
		# checking whether the given destination already exists in the list of subscribed destinations
		if {[info exists subscribedDestinations($destName)]} {
			set subscribedDestinations($destName) $callbackscript
		} else {
			if ![_subscribe $destName] {
				return 0
			}
			# Adding the given destination to the list of subscribedDestinations
			set subscribedDestinations($destName) $callbackscript
		}
		debug "Destination $destName subscribed"
		return 1
	}

	#The UNSUBSCRIBE command is used to remove an existing subscription - to no longer receive messages from that destination.
	#UNSUBSCRIBE
	#destination: /queue/foo

	public method unsubscribe {destName} {
		debug "in the unsubscribe method - '$destName'"
		debug "array [array  get subscribedDestinations]"
		if {[info exists subscribedDestinations($destName)]} {
			unset subscribedDestinations($destName)
			if ![_unsubscribe $destName] {
				debug "_unsubscribe $destName"
				return 0
			}
		} else {
			debug "subscribedDestinations($destName) not exists"
			return 0
		}
		debug "OK"
		return 1
	}
	
	#invoked when the server response frame is MESSAGE,ie, when the SUBSCRIBE Method is called
	private method on_receive {} {
		if {![info exists params(destination)]} {
			debug "destination is empty"
			return 0
		}
		set destination $params(destination)
		if {![info exists subscribedDestinations($destination)]} {
			debug "subscribedDestinations($destination) does not exist"
			return 0
		}
	
		execute $subscribedDestinations($destination) [array get params]

	}

	private method _subscribe { dest } {
		debug "calling subscribe method $dest"
		if { $isConnected && !$isError } {
			puts $connection_to_server "SUBSCRIBE"
			if {$stompVersion != "1.0"} {
				puts $connection_to_server "id:[getDestinationId $dest]"
			}
			puts $connection_to_server "destination:$dest"
			puts $connection_to_server ""
			puts $connection_to_server "\0"
			fileevent  $connection_to_server readable [list $this handleInput ]
			flush $connection_to_server
		} else {
			return 0
		}

		return 1
	}

	private method _unsubscribe { dest } {
		debug "in the _unsubscribe method - '$isConnected' && '!$isError'"
		if { $isConnected && !$isError } {
			puts $connection_to_server "UNSUBSCRIBE"
			if {$stompVersion == "1.0"} {
				puts $connection_to_server "destination:$dest"
			} else {
				puts $connection_to_server "id:[getDestinationId $dest]"
			}
			puts $connection_to_server ""
			puts $connection_to_server "\0"
			flush $connection_to_server
		} else {
			return 0
		}
		return 1
	}

	public method disconnect { } {
		if { $isConnected && !$isError } {
			puts $connection_to_server "DISCONNECT"
			puts $connection_to_server ""
			puts $connection_to_server "\0"
			fileevent  $connection_to_server readable [list $this handleInput ]
			flush $connection_to_server
			close $connection_to_server
			set isConnected 0
		} 
		return 1
	}

	public method getIsConnected { } {
		return $isConnected
	}

	public method setWriteSocketFile {status} {
		set writeSocketFile $status
	}

	public method execute {script {argsList {}}} {
		debug "im stomp execute: $script ---- | ---- $argsList"
		set argsName args
		if {$argsList == ""} {
			set argsName ""
		}
		
		#  if a global debug command is available, use it
		if [string length [info command execute_thread]] {
			debug "execute_thread $script $argsList"
			execute_thread $script $argsList
		} else {
			debug "uplevel $script $argsList"
			set procname "__[clock clicks]"
			uplevel #0 [list proc $procname $argsName $script]
			uplevel #0 [concat $procname $argsList]
			catch {uplevel #0 [list rename $procname ""]}
		}
	}

	public method getDestinationId { destination } {
		return [md5::md5 -hex $destination]
	}

	public method getStompVersion { } {
		return $stompVersion
	}
}


proc writeFile {text} {
	set fid [open tStomp.log a+]
	puts $fid $text
	close $fid
}

# if a global debug command is available, use it
if ![string length [info command debug]] {
	proc debug {msg {level ""}} {
		puts "STOMPLog: $msg"
	}
}

proc getasciivalue { string } {
	set data $string
	set output ""
	foreach char [split $data ""] {
	       	append output /[scan $char %c]
	}
	return $output
}

proc getchar { string } {
	set output ""	
       	## Split into records on newlines
        set records [split $string "/"]
       	## Iterate over the records
        for { set i 1 } { $i < [llength $records] } { incr i } {
		set rec [lindex $records $i]
		append output [format "%c" $rec]
	}
	return $output
}

