#!/bin/bash

echo_header() {
  printf "\n\e[1;33m%s\e[0m\n" "$1"
}

echo_status() {
  printf "%s %s %s\n" "---" "$1" "---"
}

contains() {
    [[ $1 =~ (^|,)$2($|,) ]] && return 0 || return 1
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
  local out_file="$3/channel-imc.csv"
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

run_imc_broker() {
  echo_status "Configuring"
  local broker_dir=$1
  local pace=$2
  local out_file="$3/broker-imc.csv"
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
  local out_file="$3/channel-kafka.csv"
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
  local out_file="$3/broker-kafka.csv"
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

run_kafka_source() {
  echo_status "Configuring"
  local source_dir=$1
  local pace=$2
  local out_file="$3/source-kafka.csv"
  kubectl apply -f "$source_dir/100-source-perf-setup.yaml"

  kubectl wait kafkatopics/perf-topic --for=condition=Ready --timeout=10m -n kafka

  kubectl apply -f "$source_dir/101-source-perf-setup.yaml"

  kubectl wait kafkasource -n perf-eventing --for=condition=Ready --all

  echo_status "Starting"
  local run_config=$(configure_test_run "$source_dir/200-source-perf.yaml" "$pace")
  ko apply -f "$run_config"

  kubectl wait pod -n perf-eventing --timeout=5m --for=condition=Ready --all

  echo_status "Collecting metrics"
  kubectl logs -n perf-eventing source-perf-aggregator mako-stub -f > "$out_file"

  echo_status "Collected test results in $out_file"

  kubectl delete -f "$source_dir/100-source-perf-setup.yaml"
}

if [[ $# -lt 2 ]]
then
  echo "Usage: $0 <tests-to-run-comma-separated> <pace-configuration> [out_dir]"
  echo "Available tests: direct, channel-imc, broker-imc, channel-kafka, broker-kafka, source-kafka"
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

echo "Do you want to process run results too (it requires a lot of time)? (yes/NO)"
read -r process_results

tests_to_run=$1
pace=$2
when=$(date +"%m-%d-%Y--%H-%M-%S")
out_dir=${3:-$when}
mkdir -p "$out_dir"

echo_header "All results will be under $out_dir"
echo "Using tests $tests_to_run"
echo "Using pace $pace"

printf "# Test run %s\nPace configuration \`%s\`\n" "$when" "$pace" > "$out_dir/README.md"

if contains "$tests_to_run" "direct"
then
  echo_header "Direct"
  run_direct "$knative_eventing_performance/direct" "$pace" "$out_dir"
fi

if contains "$tests_to_run" "channel-imc"
then
  echo_header "In Memory Channel"
  run_imc_channel "$knative_eventing_performance/channel-imc" "$pace" "$out_dir"
fi

if contains "$tests_to_run" "broker-imc"
then
  echo_header "In Memory Channel - Broker"
  run_imc_broker "$knative_eventing_performance/broker-imc" "$pace" "$out_dir"
fi

if contains "$tests_to_run" "channel-kafka"
then
  echo_header "Kafka Channel"
  run_kafka_channel "$knative_eventing_contrib_performance/channel-kafka" "$pace" "$out_dir"
fi

if contains "$tests_to_run" "broker-kafka"
then
  echo_header "Kafka Channel - Broker"
  run_kafka_broker "$knative_eventing_contrib_performance/broker-kafka" "$pace" "$out_dir"
fi

if contains "$tests_to_run" "source-kafka"
then
  echo_header "Kafka Source"
  run_kafka_source "$knative_eventing_contrib_performance/source-kafka" "$pace" "$out_dir"
fi

if [ "$process_results" == "yes" ]
then
  if contains "$tests_to_run" "direct"
  then
    echo_header "Processing direct.csv"
    bash parse_run.sh "$out_dir/direct.csv" "$out_dir/direct"
  fi
  
  if contains "$tests_to_run" "channel-imc"
  then
    echo_header "Processing channel-imc.csv"
    bash parse_run.sh "$out_dir/channel-imc.csv" "$out_dir/channel-imc"
  fi
  
  if contains "$tests_to_run" "broker-imc"
  then
    echo_header "Processing broker-imc.csv"
    bash parse_run.sh "$out_dir/broker-imc.csv" "$out_dir/broker-imc"
  fi

  if contains "$tests_to_run" "channel-kafka"
  then
    echo_header "Processing channel-kafka.csv"
    bash parse_run.sh "$out_dir/channel-kafka.csv" "$out_dir/channel-kafka"
  fi

  if contains "$tests_to_run" "broker-kafka"
  then
    echo_header "Processing broker-kafka.csv"
    bash parse_run.sh "$out_dir/broker-kafka.csv" "$out_dir/broker-kafka"
  fi

  if contains "$tests_to_run" "source-kafka"
  then
    echo_header "Processing source-kafka.csv"
    bash parse_run.sh "$out_dir/source-kafka.csv" "$out_dir/source-kafka"
  fi
fi
