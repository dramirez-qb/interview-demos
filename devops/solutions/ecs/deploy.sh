#!/bin/bash
#
# Create ECS task defintion and update service
# NOTE: The cluster, the role and the service needs to be created beforehand
#
# USAGE: deploy.sh -n cluster-name -s analysis -i bash:v0.0.1 -a 78946513 -r service-role -m 256 -c 50 -p 5000
# USAGE: deploy.sh --ecs_cluster=cluster_name --ecs_service=service_name --image_name=image_name --aws_account_id=aws_account_id --aws_role=aws_role
#

die() { echo "$*" >&2; exit 2; }  # complain to STDERR and exit with error
needs_arg() { if [ -z "$OPTARG" ]; then die "No arg for --$OPT option"; fi; }

function _usage() {
  ###### U S A G E : Help and ERROR ######
  cat <<EOF
$0 $Options
Usage: $0 <[options]>
Options:
        -a --aws_account_id   Set AWS_ACCOUNT_ID value
        -r --aws_role         Set AWS_ROLE value
        -g --aws_region       Set AWS_REGION value default us-east-1
        -n --cluster_name     Set CLUSTER_NAME value
        -s --ecs_service      Set ECS_SERVICE value
        -i --image_name       Set IMAGE_NAME value
        -m --memory           Set MEMORY value default 256
        -c --cpu              Set CPU value default 50
        -p --port             Set PORT value default 8080
EOF
exit 0
}

[ $# = 0 ] && _usage

while getopts ha:r:g:n:s:i:m:c:p:-: OPT; do
  # support long options: https://stackoverflow.com/a/28466267/519360
  if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
    OPT="${OPTARG%%=*}"       # extract long option name
    OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
    OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
  fi
  case "$OPT" in
    a | aws_account_id )    AWS_ACCOUNT_ID="$OPTARG" ;;
    r | aws_role )  needs_arg; AWS_ROLE="$OPTARG" ;;
    g | aws_region )  needs_arg; AWS_REGION="$OPTARG" ;;
    n | cluster_name )    CLUSTER_NAME="$OPTARG" ;;
    s | ecs_service )    needs_arg; ECS_SERVICE="$OPTARG" ;;
    i | image_name )  needs_arg; IMAGE_NAME="$OPTARG" ;;
    m | memory )  needs_arg; MEMORY="$OPTARG" ;;
    c | cpu )  needs_arg; CPU="$OPTARG" ;;
    p | port )  needs_arg; PORT="$OPTARG" ;;
    h | help )  _usage ;;
    ??* )          die "Illegal option --$OPT" ;;  # bad long option
    ? )            exit 2 ;;  # bad short option (error reported via getopts)
  esac
done
shift $((OPTIND-1)) # remove parsed options and args from $@ list

# more bash-friendly output for jq
JQ="jq --raw-output --exit-status"

install_aws_cli() {
  pip install --upgrade pip
  pip install --upgrade awscli
  sudo apt-get install jq
}

# Check whether to install aws clis
which aws &>/dev/null || install_aws_cli

# Set AWS region
AWS_REGION=${AWS_REGION:-us-east-1}
aws configure set default.region ${AWS_REGION}

function make_task_definition() {
	task_template='[
		{
			"name": "%s-ecs-svc",
			"image": "%s.dkr.ecr.eu-west-1.amazonaws.com/%s",
			"essential": true,
			"memory": %s,
			"cpu": %s,
			"environment": [
			    {
			        "name": "service_name",
			        "value":"%s"
			    }
			],
			"mountPoints": [
                {
                  "sourceVolume": "ecs-logs",
                  "containerPath": "/var/log/apps",
                  "readOnly": false
                },
                {
                  "sourceVolume": "ecs-data",
                  "containerPath": "/data",
                  "readOnly": false
                }
            ],
			"portMappings": [
				{
					"containerPort": %s,
					"hostPort": %s
				}
			]
		}
	]'

    task_def=$(printf "$task_template" ${ECS_SERVICE} \
                                       ${AWS_ACCOUNT_ID} \
                                       ${IMAGE_NAME} \
                                       ${MEMORY:-256} \
                                       ${CPU:-50} \
                                       ${ECS_SERVICE} \
                                       ${PORT:-8080} \
                                       ${PORT:-8080} )
}

function volume_mount_def() {
    volume_mount='[
        {
            "name": "ecs-logs",
            "host": {
                "sourcePath": "/mnt/ebs/logs/"
            }
        },
        {
            "name": "ecs-data",
            "host": {
                "sourcePath": "/mnt/ebs/data/"
            }
        }
    ]'

    volumes=$(printf "$volume_mount")
}

function register_task_definition() {
    echo "Registering task definition ${task_def}"
    if revision=$(aws ecs register-task-definition \
            --volumes "$volumes" \
            --task-role-arn $task_role_arn \
            --container-definitions "$task_def" \
            --family $family \
            --output text \
            --query 'taskDefinition.taskDefinitionArn'); then
        echo "Revision: $revision"
    else
        echo "Failed to register task definition"
        return 1
    fi

}

function deploy_service() {

    family="${ECS_SERVICE}-ecs-svc-task-family"
    echo "Family name is ${family}"
    task_role_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${AWS_ROLE}"
    echo "Task role is: ${task_role_arn}"

    make_task_definition
    volume_mount_def
    #placement_constraint_def
    register_task_definition || register_task_definition # sometimes the API fails

    if [[ $(aws ecs update-service --cluster ${CLUSTER_NAME} \
                --service ${ECS_SERVICE}-ecs-svc \
                --task-definition $revision | \
                   $JQ '.service.taskDefinition') != $revision ]]; then
        echo "Error updating service."
        return 1
    fi
}

deploy_service
