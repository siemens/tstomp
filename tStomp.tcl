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

namespace import -force ::itcl::*

#catch - Evaluate script and trap exceptional returns
catch {delete class tStomp}

class tStomp {
    #holds the Destination names the client has subscribed to
    variable subscribedDestinations
    #holds the number and name of the Queue(just like map)
    variable command
    #holds the number of destinations of the client has subscribed to
    variable handleCounter 0

    variable output ""
    #holds the ip address
    variable host
    #the port we need to connect(If ActiveMQ Message Broker is used it connects to 61613)
    variable port
    #holds the channel identifier once the channel is opened
    variable connection_to_server
    # Boolean value for checking Connection is established or not
    variable isConnected
    # Boolean value for checking if there is any error
    variable isError
    #script called on the response of "CONNECT" Command
    variable onConnectScript
    # used for Debugging purposes
    variable debugCommand tStomp::emptyLog
	#status indicates actual reading position
	variable readStatus
	#which message command is actual read
	variable readCommand
	#list of all header names of the actual read message
	variable headerNames
	#list of all header values of the actual read message
	variable headerValues

    #class called with the ipaddress and port and values are initialised in the constructor
    constructor {ip p} {} {
		set host $ip
		set port $p
		set isConnected  0
		set isError 0
		set readStatus start
    }

    #called when objects of the class are deleted
    destructor {
		disconnect
    }

    public method connect { _onConnectScript } {
		#This command opens a network socket and returns a channel identifier
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
		puts $connection_to_server "accept-version:1.0,1.1,2.0"
		puts $connection_to_server ""
		puts $connection_to_server "\0"
		set onConnectScript $_onConnectScript
		fileevent  $connection_to_server readable [list $this handleInput ]
		# Server responds with "CONNECTED" or "ERROR" frame
		flush $connection_to_server
	
    }

    # Method called whenever input arrives on a connection. Server Responses for the commands
    method handleInput { } {	

		# Delete the handler if the input was exhausted.
		if {[eof $connection_to_server ]} {
			fileevent $connection_to_server readable {}
			close     $connection_to_server
			return
		}
		
		if {$readStatus != "messagebody"} {
			switch -exact $readStatus {
				start {
					if {[gets $connection_to_server line]>0} {
						set readCommand $line
						set readStatus header
						$debugCommand "Stomp: $line"
					}
				}
				header { 
					if {[gets $connection_to_server line] > 0} {
						$debugCommand "StompHeader: $line"
						set splitHeader [split $line :]
						set varName [lindex $splitHeader 0]
						set varName [string map {- ""} $varName]
						lappend headerNames $varName
						lappend headerValues [lindex $splitHeader 1]
					} else {
						set readStatus messagebody
					}
				}
				end {
				}
				default {
					$debugCommand "default case -> not implemented yet"
				}
			}
		} else {
			set line [read $connection_to_server]	
			lappend headerNames messagebody
			lappend headerValues $line
			
			$debugCommand "Stomp: $line"
			$debugCommand "Stomp Header names: $headerNames"
			
			switch -exact $readCommand {
				CONNECTED {
					set isConnected 1
					execute $onConnectScript "" ""
				}
				MESSAGE {
					on_receive
				}
				ERROR {
					set messageBodyIndex [lsearch $headerNames messagebody]
					if {$messageBodyIndex != -1} {
						$debugCommand "Got Error: [join [lindex $headerValues $messageBodyIndex]]"
					}
				}
				RECEIPT {
					$debugCommand "Handling "RECEIPT" messages -> not implemented yet"
				}
				default {
					$debugCommand "default case -> Server message $readCommand not known!"
				}
			}
			set readStatus start
			set headerNames {}
			set headerValues {}
		}
    }

    #The SEND command sends a message to a destination in the messaging system.
    #It has one required header, destination, which indicates where to send the message.
    #The body of the SEND command is the message to be sent.
    # SEND
    # destination:/queue/foo  or /topic/foo

    #hello queue foo  or  hello topic foo

    public method send {dest msg {correlationId ""} {out ""}} {
		if { $isConnected } {
			if {$out==""} {
				#send $dest $msg $correlationId stdout
				set out $connection_to_server
			}
			puts $out "SEND"
			puts $out "destination:$dest"
				if {$correlationId!=""} {
				puts $out "correlation-id:$correlationId"
				}
			puts $out ""
			puts $out "$msg [lrange [split $dest /] 1 end]"
			puts $out "\0"
			flush $out
		}
    }

    #The SUBSCRIBE command is used to register to listen to a given destination.
    #SUBSCRIBE
    # destination: /queue/foo
    # name a callbackscript

    public method subscribe {destName name} {
		incr handleCounter
		set command($handleCounter) $name
		
		$debugCommand "Destination $destName with handleCounter $handleCounter subscribed"
		# checking whether the given destination already exists in the list of subscribed destinations
		if {![info exists subscribedDestinations($destName)]}  {
			_subscribe $destName
			set subscribedDestinations($destName) ""
		}
		# Adding the given destination to the list of subscribedDestinations
		set subscribedDestinations($destName) [struct::set union $subscribedDestinations($destName) $handleCounter]
		return $handleCounter
    }

    #The UNSUBSCRIBE command is used to remove an existing subscription - to no longer receive messages from that destination.
    #UNSUBSCRIBE
    #destination: /queue/foo

    public method unsubscribe {destName {handleCounter ""}} {		
		if {$handleCounter != ""} {
			set subscribedDestinations($destName) [struct::set exclude subscribedDestinations($destName) $handleCounter]
			unset command($handleCounter)
		} else {
			set handleCounters $subscribedDestinations($destName)
			foreach handle $handleCounters {
				unset command($handle)
			}
			unset subscribedDestinations($destName)
		}
		_unsubscribe $destName
    }
	
    #invoked when the server response frame is MESSAGE,ie, when the SUBSCRIBE Method is called
    public method on_receive {} {
		set destinationIndex [lsearch $headerNames destination]
		if {$destinationIndex  == -1} {
			$debugCommand "destination is empty"
			return
		}
	
		set destination [lindex $headerValues $destinationIndex]
		set cHandles $subscribedDestinations($destination)
		foreach c $cHandles {
			execute $command($c) $headerNames $headerValues
		}
    }

    private method _subscribe { dest } {
	$debugCommand "calling subscribe method $dest"
		if { $isConnected && !$isError } {
			puts $connection_to_server "SUBSCRIBE"
			puts $connection_to_server "destination:$dest"
			puts $connection_to_server ""
			puts $connection_to_server "\0"
			fileevent  $connection_to_server readable [list $this handleInput ]
			flush $connection_to_server
		}
    }

    private method _unsubscribe { dest } {
	$debugCommand "in the unsubscribe method"
	    if { $isConnected && !$isError } {
			puts $connection_to_server "UNSUBSCRIBE"
			puts $connection_to_server "destination:$dest"
			puts $connection_to_server ""
			puts $connection_to_server "\0"
			flush $connection_to_server
		}
    }

    public method disconnect { } {
		if { $isConnected && !$isError } {
			puts $connection_to_server "DISCONNECT"
			puts $connection_to_server ""
			puts $connection_to_server "\0"
			fileevent  $connection_to_server readable [list $this handleInput ]
			flush $connection_to_server
		}
    }

    public method execute {script nList vList} {
		set procname "__[clock clicks]"
		uplevel #0 [list proc $procname $nList $script]
		set res [uplevel #0 [concat $procname $vList]]
		catch {uplevel #0 [list rename $procname ""]}
		return $res
    }

    public method setDebug { cmd} {
		set debugCommand $cmd
    }

    proc emptyLog { s } {
	    puts "STOMPLog: $s"
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



