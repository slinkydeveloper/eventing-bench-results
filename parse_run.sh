#!/bin/bash

install_csv_matrix_processor_if_missing() {
  local CMD_NAME="csv_matrix_procesor"
  command -v "$CMD_NAME" > /dev/null || {
    echo "Command $CMD_NAME not exists, installing"
    go get -u github.com/slinkydeveloper/csv_matrix_processor
  }
}

echo_header() {
  printf "\n\e[1;33m%s\e[0m\n" "$1"
}

compute_latency_percentiles() {
  in_csv=$1
  out_csv=$2
  column=$3
  percentile=$4
  csv_processor "$in_csv" "$out_csv" << EOF
pick 0 $column
order 0
scale 1 1000
percentile 0 1 $percentile 2
order 0
pick 0 2
EOF
}

pick_throughput() {
  in_csv=$1
  out_csv=$2
  column=$3
    csv_processor "$in_csv" "$out_csv" << EOF
pick 0 $column
order 0
EOF
}

if [[ $# -lt 1 ]]
then
  echo "Usage: $0 <broker_run.csv> [out_dir]"
  exit 1
fi

install_csv_matrix_processor_if_missing

in_csv=$1
when=$(date +"%m-%d-%Y--%H-%M-%S")
out_dir=${2:-$when}
mkdir -p "$out_dir"

# echo_header "Computing percentile p99 for publish latency"
# compute_latency_percentiles "$in_csv" "$out_dir/p99-publish-latency.csv" "2" "99"

echo_header "Computing percentile p99.9 for publish latency"
compute_latency_percentiles "$in_csv" "$out_dir/p99-9-publish-latency.csv" "2" "99.9"

#echo_header "Computing percentile p99 for delivery latency"
#compute_latency_percentiles "$in_csv" "$out_dir/p99-delivery-latency.csv" "3" "99"

echo_header "Computing percentile p99.9 for delivery latency"
compute_latency_percentiles "$in_csv" "$out_dir/p99-9-delivery-latency.csv" "3" "99.9"

echo_header "Picking send throughput"
pick_throughput "$in_csv" "$out_dir/send-throughput.csv" "4"

echo_header "Picking delivery throughput"
pick_throughput "$in_csv" "$out_dir/delivery-throughput.csv" "5"
