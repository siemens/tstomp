#!/usr/bin/tclsh

# Usage: <stompUrl> <queueName>
# e.g.: "stomp://system:manager@localhost:61613" "/queue/resource.queue"

set env(TCLLIBPATH) {..}

package require tStomp
package require json
package require json::write

namespace import -force ::itcl::*

catch {delete class ServiceSimulator}

class SampleServiceClass {
    variable stompObj
    variable ttl 600000
    variable destinationQueue

    constructor {_stompObj _destinationQueue} {} {
        set stompObj $_stompObj
        set destinationQueue $_destinationQueue
    }

    public method send {correlationCounter} {

        set payload [format {
            {
        	    "name": "correlation %d",
        	    "status": "unknown",
        	    "x": 4711,
        	    "y": 4712
            }
        } $correlationCounter]

        $stompObj send -headers [list correlation-id $correlationCounter ttl $ttl class SampleServiceClass pclass SampleStatus method update] $destinationQueue $payload

    }
}

class ServiceSimulator {
    variable stompObj
    common correlationCounter 0

    variable sampleServiceClass

    constructor {stompUrl destinationQueue} {} {
        set stompObj [tStomp ::$this-stomp $stompUrl]
        $stompObj connect "$this connected"
        set sampleServiceClass [SampleServiceClass #auto $stompObj $destinationQueue]
    }

    public method connected {} {
        puts "connected"
        $this periodicSend 1000
    }

    public method periodicSend {afterInMs} {
        incr correlationCounter
        $sampleServiceClass send $correlationCounter
        after $afterInMs "$this periodicSend $afterInMs"
    }
}

ServiceSimulator #auto [lindex $argv 0] [lindex $argv 1]

vwait __forever


