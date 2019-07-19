#!/bin/bash

# exit on any error
#set -e

function usage()
{
cat << EOF
Usage: $0 cassandra-install-directory [jmx_port] [additional-delay]

This script will do a rolling-restart of a cassandra cluster. A rolling restart
is defined as performing the following sequence on each cassandra node:
  nodetool disablegossip
  nodetool disablethrift
  nodetool disablebinary
  nodetool drain
  service cassandra restart
  wait for node to come up
  wait any additional time


See the below note on how this script remotely restarts the cassandra service.

ARGUMENTS:

  cassanra-install-directory   full or relative path of install directory
                               nodetool should be located in a subdirectory
                               called "bin", yaml configuration should be
                               in conf/cassandra.yaml
  additional-delay             additional delay after a node goes up before
                               shutting down the next node.

NOTE: Remote Cassandra service restart

This script uses the following comand to restart a remote cassandra node:
	ssh -s {node} /sbin/service cassandra restart. 

This reqires that your environment be set up properly with remote ssh keys 
or you may be required to type a password.  You can set an environment variable 
to utilize a different command
CASSANDRA_RESTART_COMMAND='ssh -s ${node} /sbin/service cassandra restart'

      
Example:
	$0 ./cassandra-2.0.19 30s

EOF
}


if [[ -z "$1" ]]; then
	usage
	exit 1
fi

DIRECTORY=$1
shift

JMX_PORT=7199
if [[ ! -z "$1" ]]; then
	JMX_PORT=$1
	shift
fi

DELAY=30s
if [[ ! -z "$1" ]]; then
	DELAY=$1
	shift
fi

if [[ "$1" == "--ccm" ]]; then
	CCM=1
	ccm_index=1
	shift
fi

if [[ -z "$CASSANDRA_RESTART_COMMAND" ]]; then
	CASSANDRA_RESTART_COMMAND='ssh -s ${node} /sbin/service cassandra restart'
fi

CASSANDRA_NODETOOL_COMMAND='${DIRECTORY}/bin/nodetool -h ${node} -p ${JMX_PORT} '

if [[ $CCM == "1" ]]; then
	CASSANDRA_RESTART_COMMAND='ccm node${ccm_index} stop && ccm node${ccm_index} start'
	CASSANDRA_NODETOOL_COMMAND='${DIRECTORY}/bin/nodetool -h 127.0.0.1 -p ${JMX_PORT} '
fi


function wait_up()
{
	local node=$1
	echo "Waiting for ${node} to rejoin the ring..."
	while [[ "$(eval "$CASSANDRA_NODETOOL_COMMAND status" | grep "${node}" | awk '{print $1}')" != "UN" ]]; do
		sleep 5s
	done
}


echo "Getting listen_address for this node..."
listen_address=$(grep "^listen_address:" ${DIRECTORY}/conf/cassandra.yaml | cut -d ':' -f2)

echo "This node is listening on ${listen_address}"
echo

echo "Getting list of nodes in the cluster..."
node=$listen_address
nodes="$(eval "$CASSANDRA_NODETOOL_COMMAND status" | grep -E "^UN" | awk '{print $2}')"
echo "This script will perform a rolling restart on the following nodes:"
echo "$nodes"
echo ""

while IFS= read -r node; do 
	echo "Disable gossip on ${node}..."
	eval "$CASSANDRA_NODETOOL_COMMAND disablegossip"
	echo "Disable thrift on ${node}..."
	eval "$CASSANDRA_NODETOOL_COMMAND disablethrift"
	echo "Disable binary(cql) on ${node}..."
	eval "$CASSANDRA_NODETOOL_COMMAND disablebinary"
	echo "Draining ${node}..."
	eval "$CASSANDRA_NODETOOL_COMMAND drain"
	echo "Restarting cassandra service on ${node}..."
	eval $CASSANDRA_RESTART_COMMAND
	wait_up ${node}
	echo "Sleeping for an addition ${DELAY}..."
	sleep ${DELAY}
	echo ""

	if [[ "$CCM" == "1" ]]; then
		JMX_PORT=$((JMX_PORT+100))
		ccm_index=$((ccm_index+1))
	fi

done <<<"${nodes}"

echo "Done with Cassandra cluster rolling restart!
