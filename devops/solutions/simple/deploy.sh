#!/bin/bash

# This script is used to deploy to a simple Docker daemon running in an EC2 instance
# the CI should have access to this instance via ssh or and exposed docker daemon

#If environment variable DEBUG is set to "true" bash debug will be set. Set Debug to "verbose" for more verbose debug information
if [ "${MY_DEBUG,,}" == "true" ]; then set -x ;elif [ "${MY_DEBUG,,}" == "verbose" ]; then set -xv; fi

set -euo pipefail
IFS=$'\n\t'

IMAGE=$1
SERVICE_NAME="full_app" # Just a name for the service
CLEAN_IMAGE=${IMAGE//[^a-zA-Z0-9_-]/}


function finish {
#   /usr/bin/docker container rm -f "${SERVICE_NAME}_tmp"
  echo "Exiting..."
}

trap finish EXIT

if [ -z $1 ]; then
  echo "No image provided"
  exit 1
fi

# update image from repo
/usr/bin/docker pull $CLEAN_IMAGE

IMAGE_WITH_REPODIGESTS=$(/usr/bin/docker inspect --type image --format '{{index .RepoDigests 0}}' ${CLEAN_IMAGE})

echo "Updating service ${SERVICE_NAME} with image ${IMAGE_WITH_REPODIGESTS}"

# https://docs.docker.com/engine/reference/commandline/service_update/

CONTAINER_ID=$(/usr/bin/docker container ls -a -q -f name=${SERVICE_NAME})

if [ ! -z ${CONTAINER_ID} ]; then
  /usr/bin/docker container stop "${SERVICE_NAME}"
  /usr/bin/docker create --name="${SERVICE_NAME}_tmp" --volumes-from "${SERVICE_NAME}" ${IMAGE_WITH_REPODIGESTS}
  /usr/bin/docker container start "${SERVICE_NAME}_tmp"
  sleep 10s

  STATUS=$(/usr/bin/docker container inspect "${SERVICE_NAME}_tmp" --format "{{.State.Status}}")

  # Here should be the same arguments for the new container like ports mappings, workdir and so on !!!!!!!!!!!!
  if [[ "${STATUS}" = "running" ]]; then
      echo "All looks good with the new container."

      /usr/bin/docker container stop "${SERVICE_NAME}_tmp"
      /usr/bin/docker run -ti -d --name=${SERVICE_NAME} ${IMAGE_WITH_REPODIGESTS} --volumes-from "${SERVICE_NAME}_tmp"
      sleep 10s
      /usr/bin/docker container rm -f "${SERVICE_NAME}_tmp"
  else
      echo "The new container is not running well."
      echo "Rolling back"
      /usr/bin/docker container rm -f "${SERVICE_NAME}_tmp"
      /usr/bin/docker container start ${SERVICE_NAME}
  fi
else
  /usr/bin/docker run -ti -d --name=${SERVICE_NAME} ${IMAGE_WITH_REPODIGESTS} 
fi
