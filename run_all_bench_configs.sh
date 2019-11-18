#!/bin/bash

source ./common.sh

configure_test_run() {
  local in_file=$1
  local new_pace=$2
  local temp_file=$(mktemp)
  sed "s/--pace=[0-9,:]*/--pace=$new_pace/" "$in_file" > "$temp_file"
  echo "$temp_file"
}

reset_knative_eventing() {
  kubectl delete pods -n knative-eventing --all
  sleep 5
  kubectl wait pod -n knative-eventing --for=condition=Ready --all
}

reset_kafka() {
  kubectl delete kt --all-namespaces --all
  kubectl delete pods -n kafka my-cluster-kafka-0 my-cluster-zookeeper-0
  sleep 10
  kubectl wait pod -n kafka --for=condition=Ready --all
}

run_test() {
  local aggregator_pod=$1

  kubectl wait pod -n perf-eventing --for=condition=Ready $aggregator_pod

  echo_status "Running test"
  kubectl logs -n perf-eventing $aggregator_pod aggregator -f

  echo_status "Retrieving results from mako-stub"
  read_mako_stub_results $aggregator_pod "$out_file"
}

patch_deployments() {
  local deployment_filter=$1
  local role=$2

  patch="{\"spec\": {\"template\": {\"spec\": {\"nodeSelector\": {\"bench-role\": \"$role\" } } } } }"

  for d in $(kubectl get deployments --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' -n perf-eventing | grep "$deployment_filter");
  do
    echo_status "Patching $d deployment to use node selector bench-role: $role"
    kubectl patch -n perf-eventing deployment "$d" --patch "$patch"
    kubectl wait --for=condition=available -n perf-eventing deployment "$d"
  done

  sleep 10

  kubectl wait pod -n perf-eventing --for=condition=Ready --all
}

read_mako_stub_results() {
  local pod_name=$1
  local out_file=$2

  local script_path="$GOPATH/src/knative.dev/pkg/test/mako/stub-sidecar/read_results.sh"

  bash "$script_path" "$pod_name" perf-eventing 10001 120 100 10 "$out_file"
}

run_direct() {
  reset_knative_eventing

  echo_status "Configuring"
  local direct_dir=$1
  local pace=$2
  local out_file="$3/direct.csv"
  kubectl apply -f "$direct_dir/100-direct-perf-setup.yaml"

  echo_status "Starting"
  local run_config=$(configure_test_run "$direct_dir/200-direct-perf.yaml" "$pace")
  sleep 5
  ko apply -f "$run_config"

  run_test direct-perf-aggregator

  echo_status "Collected test results in $out_file"

  kubectl delete namespace perf-eventing
}

run_imc_channel() {
  reset_knative_eventing

  echo_status "Configuring"
  local channel_dir=$1
  local pace=$2
  local out_file="$3/channel-imc.csv"
  kubectl apply -f "$channel_dir/100-channel-perf-setup.yaml"

  kubectl wait channel -n perf-eventing --for=condition=Ready --all

  echo_status "Starting"
  local run_config=$(configure_test_run "$channel_dir/200-channel-perf.yaml" "$pace")
  sleep 5
  ko apply -f "$run_config"

  run_test channel-perf-aggregator

  echo_status "Collected test results in $out_file"

  kubectl delete namespace perf-eventing
}

run_imc_broker() {
  reset_knative_eventing

  echo_status "Configuring"
  local broker_dir=$1
  local pace=$2
  local out_file="$3/broker-imc.csv"
  kubectl apply -f "$broker_dir/100-broker-perf-setup.yaml"

  kubectl wait broker -n perf-eventing --for=condition=Ready --all

  patch_deployments broker eventing

  echo_status "Starting"
  local run_config=$(configure_test_run "$broker_dir/200-broker-perf.yaml" "$pace")
  ko apply -f "$run_config"

  run_test broker-perf-aggregator

  echo_status "Collected test results in $out_file"

  kubectl delete namespace perf-eventing
}

run_kafka_channel() {
  reset_kafka
  reset_knative_eventing

  echo_status "Configuring"
  local channel_dir=$1
  local pace=$2
  local out_file="$3/channel-kafka.csv"
  kubectl apply -f "$channel_dir/100-channel-perf-setup.yaml"

  kubectl wait channel -n perf-eventing --for=condition=Ready --timeout=10m --all

  kubectl apply -f "$channel_dir/101-channel-perf-setup.yaml"
  kubectl wait subscription.messaging.knative.dev -n perf-eventing --for=condition=Ready --timeout=10m --all
  sleep 5

  echo_status "Starting"
  local run_config=$(configure_test_run "$channel_dir/200-channel-perf.yaml" "$pace")
  sleep 5
  ko apply -f "$run_config"

  run_test channel-perf-aggregator

  echo_status "Collected test results in $out_file"

  kubectl delete namespace perf-eventing
}

run_kafka_broker() {
  reset_kafka
  reset_knative_eventing

  echo_status "Configuring"
  local broker_dir=$1
  local pace=$2
  local out_file="$3/broker-kafka.csv"
  kubectl apply -f "$broker_dir/100-broker-perf-setup.yaml"

  kubectl wait broker -n perf-eventing --for=condition=Ready --timeout=10m --all

  patch_deployments broker eventing

  echo_status "Starting"
  local run_config=$(configure_test_run "$broker_dir/200-broker-perf.yaml" "$pace")
  ko apply -f "$run_config"

  run_test broker-perf-aggregator

  echo_status "Collected test results in $out_file"

  kubectl delete namespace perf-eventing
}

run_kafka_source() {
  reset_kafka
  reset_knative_eventing

  echo_status "Configuring"
  local source_dir=$1
  local pace=$2
  local out_file="$3/source-kafka.csv"
  kubectl apply -f "$source_dir/100-source-perf-setup.yaml"

  kubectl wait kafkatopics/perf-topic --for=condition=Ready --timeout=10m -n kafka

  sleep 5

  kubectl apply -f "$source_dir/101-source-perf-setup.yaml"

  kubectl wait kafkasource -n perf-eventing --for=condition=Ready --all

  #patch_deployments kafkasource eventing

  echo_status "Starting"
  local run_config=$(configure_test_run "$source_dir/200-source-perf.yaml" "$pace")
  ko apply -f "$run_config"

  run_test source-perf-aggregator

  echo_status "Collected test results in $out_file"

  kubectl delete -f "$source_dir/100-source-perf-setup.yaml"
  kubectl delete kt --all-namespaces --all
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

check_file_exists "$GOPATH/src/knative.dev/pkg/test/mako/stub-sidecar/read_results.sh"

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
  run_direct "./configs/direct" "$pace" "$out_dir"
  sleep 5
fi

if contains "$tests_to_run" "channel-imc"
then
  echo_header "In Memory Channel"
  run_imc_channel "./configs/channel-imc" "$pace" "$out_dir"
  sleep 5
fi

if contains "$tests_to_run" "broker-imc"
then
  echo_header "In Memory Channel - Broker"
  run_imc_broker "./configs/broker-imc" "$pace" "$out_dir"
  sleep 5
fi

if contains "$tests_to_run" "channel-kafka"
then
  echo_header "Kafka Channel"
  run_kafka_channel "./configs/channel-kafka" "$pace" "$out_dir"
  sleep 5
fi

if contains "$tests_to_run" "broker-kafka"
then
  echo_header "Kafka Channel - Broker"
  run_kafka_broker "./configs/broker-kafka" "$pace" "$out_dir"
  sleep 5
fi

if contains "$tests_to_run" "source-kafka"
then
  echo_header "Kafka Source"
  run_kafka_source "./configs/source-kafka" "$pace" "$out_dir"
  sleep 5
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
