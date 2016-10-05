kafka-docker
============

Dockerfile for [Apache Kafka](http://kafka.apache.org/)

WARNING: This image is totally unsuitable for anything but research.

##How it works

A cluster consists of ZK Cluster and Kafka brokers. Each broker registers itself with the ZK nodes and uses it to discover other brokers that are part of the same cluster. Therefore each broker both communicates with ZK and its peer brokers. Docker seems to allow communication between any containers as long as you know their IP Address on the docker bridge, so we use that to simplify the cluster startup.

##Usage

Build this image as `kafka` with `make build`.

Start ZK node:

```
docker run -d --name zookeeper wurstmeister/zookeeper
```

Start 5 brokers:

```
docker run -d --name k01 --link zookeeper:zookeeper kafka
docker run -d --name k02 --link zookeeper:zookeeper kafka
docker run -d --name k03 --link zookeeper:zookeeper kafka
docker run -d --name k04 --link zookeeper:zookeeper kafka
docker run -d --name k05 --link zookeeper:zookeeper kafka
```

Start a shell for running a consumer:

```
docker run --link zookeeper:zookeeper --rm -it kafka bash
```

You will notice that we don't link in any of the nodes, for consuming (in this older version of the consumer) you only need to ask ZK for the IP address of the Leader of a partition.

Start a shell for producer:
```
docker run --link k01:k01 --link k02:k02 --link k03:k03 --link k04:k04 --link k05:k05 --rm -it kafka bash
```
The reverse is true here, ZK isn't needed for the producer, Producing to a broker that isn't a Leader will cause the broker to return the correct leader for the partition, so only one of the nodes is required here.

##Useful commands

```
$KAFKA_HOME/bin/kafka-topics.sh --zookeeper zookeeper:2181 --describe
$KAFKA_HOME/bin/kafka-topics.sh --create --replication-factor 5 --partitions 5 --zookeeper zookeeper:2181 --topic test

$KAFKA_HOME/bin/kafka-preferred-replica-election.sh --zookeeper zookeeper:2181

# Producer
$KAFKA_HOME/bin/kafka-console-producer.sh --broker-list k01:9092,k02:9091 --topic=test

# consumer
$KAFKA_HOME/bin/kafka-console-consumer.sh --zookeeper zookeeper:2181 --topic test

```

##Cleanup

Clear whole cluster

```
docker ps -aq | xargs docker rm -vf
```

Stop and start individual nodes with `docker stop -t 1 k01` and `docker start k01`
