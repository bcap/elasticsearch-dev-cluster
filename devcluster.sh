#!/bin/bash

function log() {
    echo "$(tput setaf 9)=>$(tput sgr0) $@"
}

cd $(dirname $0)

NODES=3
ES_HOME=""
ES_HTTP_PORT_START=9200
ES_TRANSPORT_PORT_START=9300
KIBANA_HOME=""
KIBANA_PORT=5601
CEREBRO_HOME=""
CLEAN=false

usage() {
cat <<EOF >&2
$(basename $0) [-n INT] [-e DIR] [-k DIR] [-c DIR] [--clean] [--http-port INT] [--transport-port INT]

Simple script to start a local Elasticsearch development cluster with multiple nodes

Options:
   -n INT --nodes INT               Number of nodes, defaults to $NODES
   -e STR --elasticsearch-home STR  Where elasticsearch is installed. By dropping this script file 
                                    at elasticsearch's bin directory, this flag can be skipped and 
                                    the cluster will use the relevant elasticsearch installation
   -k STR --kibana-home STR         Start kibana as well by passing where kibana is installed
   -c STR --cerebro-home STR        Start cerebro (https://github.com/lmenezes/cerebro) as well by passing 
                                    where it is installed
   --http-port INT                  Starting port for the http endpoint. Node 0 will use this port, 
                                    node 1 will use this port +1, and so on. Defaults to $ES_HTTP_PORT
   --transport-port INT             Starting port for the transport endpoint. Node 0 will use this port, 
                                    node 1 will use this port +1, and so on. Defaults to $ES_TRANSPORT_PORT
   --kibana-port                    When running kibana, use this port. Defaults to $KIBANA_PORT
   --clean                          DANGEROUS: start from scratch by first cleaning up all data in the cluster
   -h | --help
EOF
}

while [[ $# > 0 ]]; do
  case "$1" in
    -n|--nodes)               NODES=$2; shift ;;
    -e|--elasticsearch-home)  ES_HOME=$2; shift ;;
    -k|--kibana-home)         KIBANA_HOME=$2; shift ;;
    -c|--cerebro-home)        CEREBRO_HOME=$2; shift ;;
    --http-port)              ES_HTTP_PORT=$2; shift ;;
    --transport-port)         ES_TRANSPORT_PORT=$2; shift ;;
    --kibana-port)            KIBANA_PORT=$2; shift ;;
    --clean)                  CLEAN=true ;;
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
    echo >&2
    log "Shutting down cluster, killing pids ${SERVER_PIDS[@]}"
    kill ${SERVER_PIDS[@]}
}

if [[ $CLEAN == "true" ]]; then
    log "ATTENTION: cleaning up dir $ES_HOME/data before starting up"
    rm -rf $ES_HOME/data/*
fi

ENDPOINTS=()
for NODE_IDX in $(seq 0 $((NODES-1))); do
    NODE_NAME="node-$NODE_IDX"
    HTTP_PORT=$((ES_HTTP_PORT_START + NODE_IDX))
    TRANSPORT_PORT=$((ES_TRANSPORT_PORT_START + NODE_IDX))
    LOGS_PATH="logs/$NODE_NAME"
    ENDPOINTS+=("http://localhost:$HTTP_PORT")

    $ES_HOME/bin/elasticsearch \
        -Ecluster.name=elasticsearch-dev \
        -Enode.name="$NODE_NAME" \
        -Ehttp.port="$HTTP_PORT" \
        -Etransport.port="$TRANSPORT_PORT" \
        -Epath.logs="$LOGS_PATH" \
        -Enode.max_local_storage_nodes=$NODES \
        -Ediscovery.seed_hosts=localhost:9300 \
        -Ecluster.initial_master_nodes=node-0 &
    PID=$!

    log "Starting Elasticsearch node $NODE_NAME. PID: $PID, logs: $(realpath $ES_HOME/$LOGS_PATH), transport: localhost:$TRANSPORT_PORT, endpoint: http://localhost:$HTTP_PORT"

    SERVER_PIDS+=($PID)
done

if [[ $KIBANA_HOME != "" ]]; then
    $KIBANA_HOME/bin/kibana \
        -e $(echo ${ENDPOINTS[@]} | tr ' ' '\n' | paste -s -d ,) \
        -p $KIBANA_PORT &
    PID=$!

    log "Starting Kibana. PID: $PID, endpoint (dev tools): http://localhost:$KIBANA_PORT/app/dev_tools#/console"

    SERVER_PIDS+=($PID)
fi

if [[ $CEREBRO_HOME != "" ]]; then
    $CEREBRO_HOME/bin/cerebro &
    PID=$!

    log "Starting Cerebro. PID: $PID, endpoint: http://localhost:9000/#!/overview?host=http:%2F%2Flocalhost:$ES_HTTP_PORT_START"

    SERVER_PIDS+=($PID)
fi

for PID in ${SERVER_PIDS[@]}; do 
    wait $PID
done