#!/bin/bash

function log() {
    echo "$(tput setaf 9)=>$(tput sgr0) $@"
}

cd $(dirname $0)

NODES=3
ES_HOME=""
CLEAN=false

usage() {
cat <<EOF >&2
$(basename $0) [-n INT] [-e ELASTICSEARCH_HOME] [-c]

Simple script to start a local Elasticsearch development cluster with multiple nodes

Options:
   -n INT  --nodes INT           Number of nodes, defaults to $NODES
   -e STR  --elasticsearch-home  Where elasticsearch is installed. By dropping this
                                 script file at elasticsearch's bin directory, this
                                 flag can be skipped and the cluster will use the 
                                 relevant elasticsearch installation
   -c  --clean                   DANGEROUS: start from scratch by first cleaning up 
                                 all data in the cluster
   -h | --help
EOF
}

while [[ $# > 0 ]]; do
  case "$1" in
    -n|--nodes)               NODES=$2; shift ;;
    -e|--elasticsearch-home)  ES_HOME=$2; shift ;;
    -c|--clean)               CLEAN=true ;;
    -h|--help)                usage; exit 0 ;;
    -*)                       usage; exit 1 ;;
    *)                        tier=$1 ;;
  esac
  shift
done

if [[ $ES_HOME == "" ]]; then 
    if [ -f elasticsearch ]; then 
        $ES_HOME=..
    else
        log "-e|--elasticsearch-home was not specified and this script does not sit in elasticsearch's bin directory. Cannot find where elasticsearch is installed"
        exit 1
    fi
fi

SERVER_PIDS=()

trap cleanup SIGINT SIGQUIT

function cleanup() {
    log "Shutting down cluster, killing pids ${SERVER_PIDS[@]}"
    kill ${SERVER_PIDS[@]}
}

if [[ $CLEAN == "true" ]]; then
    log "ATTENTION: cleaning up dir $ES_HOME/data before starting up"
    rm -rf $ES_HOME/data/*
fi

log "Starting development cluster with $NODES nodes"
for NODE_IDX in $(seq 0 $((NODES-1))); do
    NODE_NAME="node-$NODE_IDX"
    PORT=$((9200 + NODE_IDX))
    TRANSPORT_PORT=$((9300 + NODE_IDX))
    LOGS_PATH="logs/$NODE_NAME"

    $ES_HOME/bin/elasticsearch \
        -Enode.name="$NODE_NAME" \
        -Ehttp.port="$PORT" \
        -Etransport.port="$TRANSPORT_PORT" \
        -Epath.logs="$LOGS_PATH" &
    PID=$!
    log "starting node $NODE_NAME at http://localhost:$PORT with pid $PID"
    SERVER_PIDS+=($PID)
done

for PID in ${SERVER_PIDS[@]}; do 
    wait $PID
done
