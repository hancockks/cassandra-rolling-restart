cassandra-rolling-restart
======================

A simple bash script which follows best practices for performing a 
rolling restart of a Cassandra cluster. The script utilizes nodetool status
to determine every node in the ring and then executes the following
commands to cleanly shut down each node:
* nodetool disablegossip
* nodetool disablethrift
* nodetool disablebinary
* nodetool drain
* service cassandra restart
* (poll for node to rejoin ring)
* (wait an optional extra period of time)

### Usage

cassandra-rolling-restart.sh cassandra-install-directory [jmx_port] [additional-delay]

#### Apologies

Apologies to anyone who might have already provided such a script, but my google-foo failed
so I probably reinvented the wheel again. 
