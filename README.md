# Knative Eventing benchmarks scripts and results

Collections of scripts and test results for various Knative Eventing benchmakrs

## Requirements

### Nodes labels

- `bench-role: kafka`: Where Kafka should live
- `bench-role: eventing`: Where eventing data-plane lives
- `bench-role: sender`: Where sender lives
- `bench-role: receiver`: Where receiver lives

If sender and receiver are in the same pod, sender is used 

## Run in bare metal k8s cluster

### `strimzi_persisted_cluster.sh`

Start kafka persisted custer

### `knative_eventing.sh`

Install knative eventing and apply patches to run in specific nodes

## Run in OCP

### `prepare-ocp-cluster.sh`

Script that configures a newly created OCP cluster with Strimzi, Knative Eventing and Knative Kafka operators.

It **doesn't** assign the node lables, you should do manually

## Test scripts

### `parse_run.sh`

Script to process a run result using https://github.com/slinkydeveloper/csv_matrix_processor/ . The output is a directory with different CSVs

### `plot.plg`

Gnuplot script that reads processed CSVs created with `parse_run.sh` and plots throughput and latencies in the same graph. Usage:

```
gnuplot -c plot.plg <directory> <latency_upper_bound> <throughput_lower_bound> <throughput_higher_bound>
```

Example:

```
gnuplot -c plot.plg 09-25-2019--13-44-03/direct 200 100 1200
```

### `run_all_bench_configs.sh`

Script to run all benchmarks configurations (direct, channel-imc, channel-kafka, broker-imc, broker-kafka, source-kafka) using the same pace.
It also optionally invokes `parse_run.sh` to process the test results

The script patches deployments of sources and brokers to run in nodes labelled with `bench-role: eventing`