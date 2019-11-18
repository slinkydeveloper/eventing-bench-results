#!/bin/bash

source ./common.sh

check_command_exists kubectl

strimzi_version=$(curl https://github.com/strimzi/strimzi-kafka-operator/releases/latest |  awk -F 'tag/' '{print $2}' | awk -F '"' '{print $1}' 2>/dev/null)

echo_header "Strimzi ${strimzi_version} install"
kubectl create namespace kafka
curl -L "https://github.com/strimzi/strimzi-kafka-operator/releases/download/${strimzi_version}/strimzi-cluster-operator-${strimzi_version}.yaml" \
  | sed 's/namespace: .*/namespace: kafka/' \
  | kubectl -n kafka apply -f -

kubectl wait --for condition=Available -n kafka deployment/strimzi-cluster-operator

echo_header "Applying Strimzi Cluster file"
kubectl -n kafka apply -f kafka_cluster_ephemeral.yaml
echo_header "Waiting for Strimzi to become ready"
sleep 5; while echo && kubectl get pods -n kafka | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done