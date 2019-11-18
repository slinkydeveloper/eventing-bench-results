# Test run 11-14-2019

## Environment

Bare metal cluster with three Dell Poweredge R6415, CPU AMD EPYC 7401P 24-Core Processor, 24Gb memory.

Labels:

* Node1: `bench-role: eventing` + etcd + master kube node (apiserver, controller, etc)
* Node2: `bench-role: kafka`
* Node3: `bench-role: sender`

Servers are on the same rack and are connected with 1Gb Ethernet. 940Mbit/s is the thpt between machines (iperf)

Kubernetes v1.15.6, docker container engine, flannel networking and iptables kube-proxy mode

## Test

GC is on in the receiver pod, while GC is run *only* between paces in the sender pod. Disabled GC messages between paces.

Kafka topics used in channel-kafka, broker-kafka and source-kafka have 100 partitions.

Payloads of the messages are 100 bytes long.

Two different pace configurations are tested:

* 1k-2k: `1000:30,1100:30,1200:30,1300:30,1400:30,1500:30,100:60,1600:30,1700:30,1800:30,1900:30,2000:30`
* 1k-long: `1000:360` (only channel-imc, broker-imc, channel-kafka, broker-kafka)

The first one should prove the breaking points of the SUT, while the second one should help finding an e2e latency measurement.