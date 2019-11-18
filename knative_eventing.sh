#!/bin/bash

source ./common.sh

check_command_exists kubectl

eventing_version="v0.10.0"

echo_status "Installing Knative Eventing ${eventing_version}"

kubectl apply --filename https://github.com/knative/eventing/releases/download/${eventing_version}/release.yaml
sleep 5
ko apply -f "${GOPATH}/src/knative.dev/eventing-contrib/kafka/channel/config"
ko apply -f "${GOPATH}/src/knative.dev/eventing-contrib/kafka/source/config"

# Patch to run data-plane in specific nodes

patch='{"spec": {"template": {"spec": {"nodeSelector": {"bench-role": "eventing" } } } } }'

kubectl patch -n knative-eventing deployment/imc-dispatcher --patch "$patch"
kubectl patch -n knative-eventing deployment/kafka-ch-dispatcher --patch "$patch"

kubectl delete pods --all -n knative-eventing

echo_header "Waiting for Knative Eventing to become ready"
sleep 5; while echo && kubectl get pods -n knative-eventing | grep -v -E "(Running|Completed|STATUS)"; do sleep 5; done