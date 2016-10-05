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

## Resilience Research

We wanted to test what happens with different topic configurations during several broker failures. Specifically understand how to make Kafka cluster fully consistent while surviving `f` failures, and more, sacrificing availability to keep consistency.

Start a cluster and create a topic with 1 partition and 3 replicas. Get a shell in any of the nodes and run describe:

```
bash-4.3# $KAFKA_HOME/bin/kafka-topics.sh --zookeeper zookeeper:2181 --describe
Topic:test	PartitionCount:1	ReplicationFactor:3	Configs:
	Topic: test	Partition: 0	Leader: 1	Replicas: 1,3,4	Isr: 1,3,4
```

Leader is Broker 1, with 1,3,4 being in sync. In sync replicas are written synchronously to ensure that the data is replicated properly, By default Kafka is configured to be Available, meaning it will let you write to the leader even if ISR is only consists of 1 node. In this case if the leader goes so will your newly written data.

We can re-configure Kafka to favour consistency by having the producer `ack=all` setting, which tells the broker to only ack a write if its been propagated to all of the ISR. We can also add an option to topic creation to refuse writes if ISR is smaller than half of the cluster. This means that there can never be a condition that a network partition creates two clusters both accepting writes.

```
$KAFKA_HOME/bin/kafka-topics.sh --create --replication-factor 3 --partitions 1 --zookeeper zookeeper:2181 --topic test --config min.insync.replicas=2

Topic:test	PartitionCount:1	ReplicationFactor:3	Configs:min.insync.replicas=2
	Topic: test	Partition: 0	Leader: 5	Replicas: 5,2,3	Isr: 5,2,3
```

This cluster can now survive at least 1 failure and maintain Consistency and Availability. 2 failures will sacrifice Availability to keep the data consistent: We cannot accept a write with 1 node in ISR because there is nowhere else to replicate that write to.

The formula goes like this:

```
Where f is number of failures we want to tolerate:

Replication setting = f x 2 + 1
Minimum ISR size    = f + 1
```

To survive 2 failures we need `2 x 2 + 1 = 5` replicas, with minimum ISR of `2 + 1 = 3`.

To survive just 1 failure `1 x 2 + 1 = 3` replicas, with minimum ISR of `1 + 1 = 2`

Three failures is `3 x 2 + 1 = 7` replicas, with minimum ISR of `3 + 1 = 4`

These are minimum settings to maintain availability *and* consistency in face of failures. Minimum settings to maintain just consistency are `f + 1` for both, any failure above `f` will just limit availability

## Performance

Of course we can't just keep adding nodes to the ISR with impunity: Since all nodes are written in sync our response equals the response time of the slowest node in the ISR. With more nodes you get higher chance of outliers ruining your average response.

Scaling kafka in general:

1. Increasing the size of ISR increases availability at expense of response time
2. Increasing the minimum ISR size increases consistency at the expense of availability during failures
3. To spread the load of leaders across the cluster create more partitions for your topics
4. Increase the number of nodes to match the number of leaders (`=` partitions) you have

Off the top of my head I would recommend a cluster with `f=2` so, `5` nodes, a topic with `5` partitions, `3` replicas, with `2` minimum ISR. This doesn't leave much room for growth but should work as a solid cluster with ability to survive a downed node *or* a rolling restart at the same time without loss of Availability. Consistency will be maintained as long as at least 1 node is healthy.

I couldn't have done this research without @RichardHe-awin, so props!
