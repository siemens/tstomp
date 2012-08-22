Software requirements:
- JMeter: http://jmeter.apache.org/download_jmeter.cgi
- ActiveMQ 5.6.0: http://activemq.apache.org/activemq-560-release.html
- SLF4J: http://www.slf4j.org/download.html

Step by step guide to configure and execute JMeter with ActiveMQ:

1)	The following jars must be added in the lib folder of JMeter:
		a) activemq-all-5.6.0.jar (from ActiveMQ 5.6.0)
		b) activemq-core-5.6.0.jar (from ActiveMQ 5.6.0)
		c) geronimo-j2ee-management_1.1_spec-1.0.1.jar (from ActiveMQ 5.6.0)
		d) slf4j-simple-1.6.6.jar (from SLF4J)
		e) slf4j-api-1.6.6.jar (from SLF4J)

2) Ensure the EchoTest.tcl file is properly configured with the correct broker host name and port.
		e.g. tStomp ::s localhost 61613

3) Start TCL console and source the EchoTest.tcl script (e.g. source path/EchoTest.tcl).

4) In the "conf" directory of ActiveMQ, edit the "activemq.xml" file and set up the transport connectors as appropriate.
	e.g. <transportConnectors>
                <transportConnector name="openwire" uri="tcp://0.0.0.0:61616"/>
                <transportConnector name="stomp" uri="stomp://0.0.0.0:61612?transport.closeAsync=false"/>
                <transportConnector name="stomp+nio" uri="stomp+nio://0.0.0.0:61613?transport.closeAsync=false"/>
        </transportConnectors>

5) If you are running ActiveMQ locally, on Windows e.g. execute "activemq.bat".

6) Check that ActiveMQ is working properly by accessing it from the web browser:
		e.g. http://localhost:8161/

7) Execute JMeter.bat which can be found in the bin directory of JMeter.

8) In JMeter, open the testplan file "ActiveMQPublishSubscribe.jmx" provided and execute Start from the Run menu.
JMeter starts two tasks, Publisher and Subscriber, and it publishes 1000 messages and subscribes 1000 messages.

Typical throughput on a test evironment with local JMeter, local ActiveMQ and local EchoTest.tcl, with Intel Core i7 2720, 2012-06-25:
	44 messages per second (with persitent messages) for both publishing and subscribing
	46 messages per second (without persitence) for both publishing and subscribing.