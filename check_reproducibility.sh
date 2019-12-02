#!/bin/bash

iterations=10

test_type=$1
pace=$2

for i in $(seq 1 $iterations);
  do echo "Iteration $i";
  echo "yes" | ./run_all_bench_configs.sh $test_type $pace ${test_type}-reproducibility-${i}
done

echo "-- P99 --"
argument=""
for i in $(seq 1 $iterations); do
  argument="${argument} ${test_type}-reproducibility-${i}/$test_type"
done
./print_last_lines.sh p99-delivery-latency $argument

echo "-- P99.9 --"
argument=""
for i in $(seq 1 $iterations); do
  argument="${argument} ${test_type}-reproducibility-${i}/$test_type"
done
./print_last_lines.sh p99-9-delivery-latency $argument

echo "-- P99.99 --"
argument=""
for i in $(seq 1 $iterations); do
  argument="${argument} ${test_type}-reproducibility-${i}/$test_type"
done
./print_last_lines.sh p99-99-delivery-latency $argument