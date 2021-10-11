#!/bin/bash

# This script is used to deploy to a Kubernetes cluster
# USAGE: deploy.sh namespace newimage

#If environment variable DEBUG is set to "true" bash debug will be set. Set Debug to "verbose" for more verbose debug information
if [ "${MY_DEBUG,,}" == "true" ]; then set -x ;elif [ "${MY_DEBUG,,}" == "verbose" ]; then set -xv; fi

IFS=$'\n\t'

function _usage(){
  cat <<EOF
$0 $@
  Usage: $0 namespace newimage
EOF
exit 0
}

[ $# = 0 ] && _usage

if [ -z $1 ]; then
  echo "No namespace provided"
  exit 1
fi

if [ -z $2 ]; then
  echo "No image provided"
  exit 2
fi

set -euo pipefail

NAMESPACE=$1
CLEAN_NAMESPACE=${NAMESPACE//[^a-zA-Z0-9\_\-]/} # clean the user input
IMAGE=$2
CLEAN_IMAGE=${IMAGE//[^a-zA-Z0-9\_\-\.\/\:]/} # clean the user input

echo "Deploying with image ${CLEAN_IMAGE} inside ${CLEAN_NAMESPACE} namespace"

kubectl get ns ${CLEAN_NAMESPACE} > /dev/null 2>&1 || (echo "${CLEAN_NAMESPACE} namespace doesn't exist"; exit 1234)

if [[ -f kustomization.yaml ]]; then
  kustomize edit set image ${CLEAN_IMAGE} # the image must match the deployment like dxas90/network-stats:v0.0.1 this is used to change only the tag
  kubectl -n ${CLEAN_NAMESPACE} apply -k .
  kubectl -n ${CLEAN_NAMESPACE} rollout status deployment network-stats
fi
