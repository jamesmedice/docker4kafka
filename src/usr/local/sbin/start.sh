#! /usr/bin/env bash

# Fail hard and fast
set -eo pipefail

# Evaluate commands
for VAR in $(env)
do
  if [[ $VAR =~ ^KAFKA_.*_COMMAND= ]]; then
    VAR_NAME=${VAR%%=*}
    EVALUATED_VALUE=$(eval ${!VAR_NAME})
    export ${VAR_NAME%_COMMAND}=${EVALUATED_VALUE}
    echo "${VAR} -> ${VAR_NAME%_COMMAND}=${EVALUATED_VALUE}"
  fi
done

# Check mandatory parameters
if [ -z "$KAFKA_BROKER_ID" ]; then
  echo "\$KAFKA_BROKER_ID not set"
  exit 1
fi
echo "KAFKA_BROKER_ID=$KAFKA_BROKER_ID"

if [ -z "$KAFKA_ADVERTISED_HOST_NAME" ]; then
  echo "\$KAFKA_ADVERTISED_HOST_NAME not set"
  exit 1
fi
echo "KAFKA_ADVERTISED_HOST_NAME=$KAFKA_ADVERTISED_HOST_NAME"

if [ -z "$KAFKA_ZOOKEEPER_CONNECT" ]; then
  echo "\$KAFKA_ZOOKEEPER_CONNECT not set"
  exit 1
fi
echo "KAFKA_ZOOKEEPER_CONNECT=$KAFKA_ZOOKEEPER_CONNECT"

KAFKA_LOCK_FILE="/var/lib/kafka/.lock"
if [ -e "${KAFKA_LOCK_FILE}" ]; then
  echo "removing stale lock file"
  rm ${KAFKA_LOCK_FILE}
fi

export KAFKA_LOG_DIRS=${KAFKA_LOG_DIRS:-/var/lib/kafka}

echo "" >> $KAFKA_HOME/config/server.properties

# General config
for VAR in `env`
do
  if [[ $VAR =~ ^KAFKA_ && ! $VAR =~ ^KAFKA_HOME ]]; then
    KAFKA_CONFIG_VAR=$(echo "$VAR" | sed -r "s/KAFKA_(.*)=.*/\1/g" | tr '[:upper:]' '[:lower:]' | tr _ .)
    KAFKA_ENV_VAR=${VAR%%=*}

    if egrep -q "(^|^#)$KAFKA_CONFIG_VAR" $KAFKA_HOME/config/server.properties; then
      sed -r -i "s (^|^#)$KAFKA_CONFIG_VAR=.*$ $KAFKA_CONFIG_VAR=${!KAFKA_ENV_VAR} g" $KAFKA_HOME/config/server.properties
    else
      echo "$KAFKA_CONFIG_VAR=${!KAFKA_ENV_VAR}" >> $KAFKA_HOME/config/server.properties
    fi
  fi
done

# *********** Creating Kafka Topics**************
#kafka create topics
# Expected format:
#   name:partitions:replicas:cleanup.policy
IFS="${KAFKA_CREATE_TOPICS_SEPARATOR-,}"; for topicToCreate in $KAFKA_CREATE_TOPICS; do
    echo "creating topics: $topicToCreate"
    IFS=':' read -r -a topicConfig <<< "$topicToCreate"
    config=
    if [ -n "${topicConfig[3]}" ]; then
        config="--config=cleanup.policy=${topicConfig[3]}"
    fi

    COMMAND="JMX_PORT='' ${KAFKA_HOME}/bin/kafka-topics.sh \\
		--create \\
		--zookeeper ${KAFKA_ZOOKEEPER_CONNECT} \\
		--topic ${topicConfig[0]} \\
		--partitions ${topicConfig[1]} \\
		--replication-factor ${topicConfig[2]} \\
		${config} \\
		${KAFKA_0_10_OPTS} &"
    eval "${COMMAND}"
done

# Logging config
sed -i "s/^kafka\.logs\.dir=.*$/kafka\.logs\.dir=\/var\/log\/kafka/" /opt/kafka/config/log4j.properties
export LOG_DIR=/var/log/kafka

su kafka -s /bin/bash -c "cd /opt/kafka && bin/kafka-server-start.sh config/server.properties"