#!/bin/bash

echo_header() {
  printf "\n\e[1;33m%s\e[0m\n" "$1"
}

echo_status() {
  printf "%s %s %s\n" "---" "$1" "---"
}

check_command_exists() {
  CMD_NAME=$1
  CMD_INSTALL_WITH=$([ -z "$2" ] && echo "" || printf "\nInstall using '%s'" "$2")
  command -v "$CMD_NAME" > /dev/null || {
    echo "Command $CMD_NAME not exists$CMD_INSTALL_WITH"
    exit 1
  }
}

check_dir_exists() {
  DIR=$1
  if ! [ -d "$DIR" ]; then
    echo "Cannot find $DIR"
    exit 1
  fi
}

configure_test_run() {
  local in_file=$1
  local new_pace=$2
  local temp_file=$(mktemp)
  sed "s/--pace=[0-9,:]*/--pace=$new_pace/" "$in_file" > "$temp_file"
  echo "$temp_file"
}

run_direct() {
  echo_status "Configuring"
  local direct_dir=$1
  local pace=$2
  local out_file="$3/direct.csv"
  kubectl apply -f "$direct_dir/100-direct-perf-setup.yaml"

  echo_status "Starting"
  local run_config=$(configure_test_run "$direct_dir/200-direct-perf.yaml" "$pace")
  ko apply -f "$run_config"

  kubectl wait pod -n perf-eventing --for=condition=Ready --all

  echo_status "Collecting metrics"
  kubectl logs -n perf-eventing direct-perf-aggregator mako-stub -f > "$out_file"

  echo_status "Collected test results in $out_file"

  kubectl delete namespace perf-eventing
}

run_imc_channel() {
  echo_status "Configuring"
  local channel_dir=$1
  local pace=$2
  local out_file="$3/imc-channel.csv"
  kubectl apply -f "$channel_dir/100-channel-perf-setup.yaml"

  kubectl wait channel -n perf-eventing --for=condition=Ready --all

  echo_status "Starting"
  local run_config=$(configure_test_run "$channel_dir/200-channel-perf.yaml" "$pace")
  ko apply -f "$run_config"

  kubectl wait pod -n perf-eventing --for=condition=Ready --all

  echo_status "Collecting metrics"
  kubectl logs -n perf-eventing channel-perf-aggregator mako-stub -f > "$out_file"

  echo_status "Collected test results in $out_file"
}

run_imc_broker() {
  echo_status "Configuring"
  local broker_dir=$1
  local pace=$2
  local out_file="$3/imc-broker.csv"
  kubectl apply -f "$broker_dir/100-broker-perf-setup.yaml"

  kubectl wait broker -n perf-eventing --for=condition=Ready --all

  echo_status "Starting"
  local run_config=$(configure_test_run "$broker_dir/200-broker-perf.yaml" "$pace")
  ko apply -f "$run_config"

  kubectl wait pod -n perf-eventing --for=condition=Ready --all

  echo_status "Collecting metrics"
  kubectl logs -n perf-eventing broker-perf-aggregator mako-stub -f > "$out_file"

  echo_status "Collected test results in $out_file"

  kubectl delete namespace perf-eventing
}

run_kafka_channel() {
  echo_status "Configuring"
  local channel_dir=$1
  local pace=$2
  local out_file="$3/kafka-channel.csv"
  kubectl apply -f "$channel_dir/100-channel-perf-setup.yaml"

  kubectl wait channel -n perf-eventing --for=condition=Ready --all

  echo_status "Starting"
  local run_config=$(configure_test_run "$channel_dir/200-channel-perf.yaml" "$pace")
  ko apply -f "$run_config"

  kubectl wait pod -n perf-eventing --for=condition=Ready --all

  echo_status "Collecting metrics"
  kubectl logs -n perf-eventing channel-perf-aggregator mako-stub -f > "$out_file"

  echo_status "Collected test results in $out_file"

  kubectl delete namespace perf-eventing
}

run_kafka_broker() {
  echo_status "Configuring"
  local broker_dir=$1
  local pace=$2
  local out_file="$3/kafka-broker.csv"
  kubectl apply -f "$broker_dir/100-broker-perf-setup.yaml"

  kubectl wait broker -n perf-eventing --for=condition=Ready --all

  echo_status "Starting"
  local run_config=$(configure_test_run "$broker_dir/200-broker-perf.yaml" "$pace")
  ko apply -f "$run_config"

  kubectl wait pod -n perf-eventing --for=condition=Ready --all

  echo_status "Collecting metrics"
  kubectl logs -n perf-eventing broker-perf-aggregator mako-stub -f > "$out_file"

  echo_status "Collected test results in $out_file"

  kubectl delete namespace perf-eventing
}

if [[ $# -lt 1 ]]
then
  echo "Usage: $0 <pace-configuration> [out_dir]"
  exit 1
fi

if [ -z "$KO_DOCKER_REPO" ]
then
      echo "\$KO_DOCKER_REPO not configured"
      exit 1
fi

check_command_exists kubectl
check_command_exists ko

knative_eventing_performance="$GOPATH/src/knative.dev/eventing/test/performance"
knative_eventing_contrib_performance="$GOPATH/src/knative.dev/eventing-contrib/test/performance"

check_dir_exists "$knative_eventing_performance"
check_dir_exists "$knative_eventing_contrib_performance"

echo "Do you want to process run results too (it requires a lot of time)?(yes/NO)"
read -r process_results

pace=$1
when=$(date +"%m-%d-%Y--%H-%M-%S")
out_dir=${2:-$when}
mkdir -p "$out_dir"

echo_header "All results will be under $out_dir"
echo "Using pace $pace"

printf "# Test run %s\nPace configuration \`%s\`\n" "$when" "$pace" > "$out_dir/README.md"

echo_header "Direct"
run_direct "$knative_eventing_performance/direct" "$pace" "$out_dir"

echo_header "In Memory Channel"
run_imc_channel "$knative_eventing_performance/channel-imc" "$pace" "$out_dir"

echo_header "In Memory Channel - Broker"
run_imc_channel "$knative_eventing_performance/broker-imc" "$pace" "$out_dir"

echo_header "Kafka Channel"
run_imc_channel "$knative_eventing_contrib_performance/channel-kafka" "$pace" "$out_dir"

echo_header "Kafka Channel - Broker"
run_imc_channel "$knative_eventing_contrib_performance/broker-kafka" "$pace" "$out_dir"

if [ "$process_results" == "yes" ]
then
  echo_header "Processing direct.csv"
  bash parse_run.sh "$out_dir/direct.csv" "$out_dir/direct"
  
  echo_header "Processing imc-channel.csv"
  bash parse_run.sh "$out_dir/imc-channel.csv" "$out_dir/imc-channel"
  
  echo_header "Processing imc-broker.csv"
  bash parse_run.sh "$out_dir/imc-broker.csv" "$out_dir/imc-broker"
  
  echo_header "Processing kafka-channel.csv"
  bash parse_run.sh "$out_dir/kafka-channel.csv" "$out_dir/kafka-channel"
  
  echo_header "Processing kafka-broker.csv"
  bash parse_run.sh "$out_dir/kafka-broker.csv" "$out_dir/kafka-broker"
fi
