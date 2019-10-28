#!/usr/bin/env sh

check_command_exists() {
  CMD_NAME=$1
  CMD_INSTALL_WITH=$([ -z "$2" ] && echo "" || printf "\nInstall using '%s'" "$2")
  command -v "$CMD_NAME" > /dev/null || {
    echo "Command $CMD_NAME not exists$CMD_INSTALL_WITH"
    exit 1
  }
}

function scale_up_workers(){
  local cluster_api_ns="openshift-machine-api"

  oc get machineset -n ${cluster_api_ns} --show-labels

  # Get the machinesets
  local machinesets=$(oc get machineset -n ${cluster_api_ns} -o custom-columns="name:{.metadata.name},replicas:{.spec.replicas}" | grep " [01]" | head -n 6 | awk '{printf "%s\n",$1}')

  IFS=$'\n'

  for machineset in $machinesets; do
    oc patch machineset -n ${cluster_api_ns} ${machineset} -p '{"spec":{"replicas":6}}' --type=merge
  done

  for machineset in $machinesets; do
    wait_until_machineset_scales_up ${cluster_api_ns} ${machineset} 6
  done
}

# Waits until the machineset in the given namespaces scales up to the
# desired number of replicas
# Parameters: $1 - namespace
#             $2 - machineset name
#             $3 - desired number of replicas
function wait_until_machineset_scales_up() {
  echo -n "Waiting until machineset $2 in namespace $1 scales up to $3 replicas"
  for i in {1..150}; do  # timeout after 15 minutes
    local available=$(oc get machineset -n $1 $2 -o jsonpath="{.status.availableReplicas}")
    if [[ ${available} -eq $3 ]]; then
      echo -e "\nMachineSet $2 in namespace $1 successfully scaled up to $3 replicas"
      return 0
    fi
    echo -n "."
    sleep 6
  done
  echo - "\n\nError: timeout waiting for machineset $2 in namespace $1 to scale up to $3 replicas"
  return 1
}

function install_strimzi() {
  kubectl create namespace kafka

  local strimzi_version=`curl https://github.com/strimzi/strimzi-kafka-operator/releases/latest |  awk -F 'tag/' '{print $2}' | awk -F '"' '{print $1}' 2>/dev/null`

  curl -L "https://github.com/strimzi/strimzi-kafka-operator/releases/download/${strimzi_version}/strimzi-cluster-operator-${strimzi_version}.yaml" \
    | sed 's/namespace: .*/namespace: kafka/' \
    | kubectl -n kafka apply -f -
  kubectl -n kafka apply -f "https://raw.githubusercontent.com/strimzi/strimzi-kafka-operator/${strimzi_version}/examples/kafka/kafka-persistent-single.yaml"

  kubectl wait kafka/my-cluster --for=condition=Ready --timeout=10m -n kafka
}

function install_knative_eventing() {
  echo "Installing Knative Eventing"
  go_path=$1
  GOPATH=$go_path
  local eventing_operator_dir="$go_path/src/github.com/openshift-knative/knative-eventing-operator"
  git clone git@github.com:openshift-knative/knative-eventing-operator.git "$eventing_operator_dir"
  kubectl apply -f "$eventing_operator_dir/deploy/crds/eventing_v1alpha1_knativeeventing_crd.yaml"
  kubectl apply -f "$eventing_operator_dir/deploy/"
  kubectl wait --for=condition=Available deployment/knative-eventing-operator --timeout=10m
  kubectl apply -f "$eventing_operator_dir/deploy/crds/eventing_v1alpha1_knativeeventing_cr.yaml"
  sleep 5
  kubectl wait --for=condition=Ready --all pod --timeout=10m -n knative-eventing
  echo "Knative Eventing ready"
}

function install_knative_eventing_kafka() {
  echo "Installing Knative Eventing Kafka"
  go_path=$1
  GOPATH=$go_path
  local kafka_operator_dir="$go_path/src/github.com/openshift-knative/knative-kafka-operator"
  git clone git@github.com:openshift-knative/knative-kafka-operator.git "$kafka_operator_dir"
  kubectl apply -f "$kafka_operator_dir/deploy/crds/eventing_v1alpha1_knativeeventingkafka_crd.yaml"
  kubectl apply -f "$kafka_operator_dir/deploy/"
  kubectl wait --for=condition=Available deployment/knative-kafka-operator --timeout=10m

  boostrap_server=$(kubectl get kafka -n kafka -o=jsonpath="{.items[0].status.listeners[0].addresses[0].host}{':'}{.items[0].status.listeners[0].addresses[0].port}")

  cat <<-EOF | kubectl apply -f -
apiVersion: eventing.knative.dev/v1alpha1
kind: KnativeEventingKafka
metadata:
  name: knative-eventing-kafka
  namespace: knative-eventing
spec:
  bootstrapServers: "$boostrap_server"
  setAsDefaultChannelProvisioner: no
EOF
  sleep 5
  kubectl wait --for=condition=Ready --all pod --timeout=10m -n knative-eventing
  echo "Knative Eventing Kafka ready"
}

function install_service_elasticsearch() {
  cat <<-EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: elasticsearch
  namespace: openshift-operators
spec:
  channel: preview
  name: elasticsearch-operator
  source: devint-operators
  sourceNamespace: openshift-operators
  installPlanApproval: Automatic
EOF
  sleep 5
  
}

if [ -z "$KO_DOCKER_REPO" ]
then
      echo "\$KO_DOCKER_REPO not configured"
      exit 1
fi

echo "This script assumes the cluster is a newly created Openshift 4.1 cluster"

check_command_exists oc
check_command_exists kubectl
check_command_exists ko

scale_up_workers

temp_go_path=$(mktemp -d)

install_strimzi
install_knative_eventing "$temp_go_path"
install_knative_eventing_kafka "$temp_go_path"
