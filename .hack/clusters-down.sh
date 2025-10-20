#!/bin/bash
set -e

# Teardown the clusters
minikube delete -p control-cluster
minikube delete -p stage-cluster
minikube delete -p prod-cluster
minikube delete -p monitoring-cluster

