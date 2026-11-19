#!/bin/bash
## =====================================================================
##  crew.remote: worker machines on AWS, one EC2 Fleet of spot instances
##  in one region, each running worker-data.sh (unofficial; not part of crew)
##
##    launch_workers.sh <region> <machines> <run name> <hours>
##
##  Settings, as environment variables (CREW_REMOTE_...):
##    BUCKET         S3 bucket for the worker command, logs and "done"
##    BUCKET_REGION  the bucket's region
##    WORKER_ROLE    instance profile that may read the bucket and write the
##                   workers' logs (default crew-remote-worker, made by setup.sh)
##    REPO           git repository of the project (https URL)
##    CODE           the commit to run ("" for the default branch), or an
##                   s3:// .tar.gz of the project; the boss's code
##    IMAGE          Docker image with the project's environment
##    WORKER_COMMAND what runs the workers in the image, from the project
##                   folder (e.g. "Rscript worker.R cache/remote/worker_call.R")
##    DOCKER_OPTIONS extra options for docker run (e.g. "-e SMOKE=1"), optional
##    CALL_FILE      where the command calls the worker command file
##                   (default cache/remote/worker_call.R)
##    TYPES          instance types (default: AMD 32-vCPU types, 32 real
##                   cores; Intel's 32 vCPUs are 16 hyperthreaded cores)
##    CAPACITY_REBALANCE  1: when AWS signals that a machine is at risk of
##                   being taken back, start its replacement at once (needs
##                   spot quota for one machine more; default 0)
##
##  The machines have encrypted disks, require IMDSv2, and sit in a security
##  group with no inbound rules (crew-remote-workers): nothing can connect to
##  them; they only dial out. The fleet is of type "maintain": when AWS takes
##  a machine back, the fleet starts another. It ends after <hours>, and its machines with it
##  (the safety cutoff); the boss deletes it when the run is done. The
##  machines are tagged crew-remote-run = <run name>, by which the boss
##  finds them. Needs the AWS command line tool, logged in.
## =====================================================================
set -euo pipefail
REGION="$1"
MACHINES="$2"
RUN_NAME="$3"
HOURS="$4"
: "${CREW_REMOTE_BUCKET:?}" "${CREW_REMOTE_BUCKET_REGION:?}"
CREW_REMOTE_WORKER_ROLE="${CREW_REMOTE_WORKER_ROLE:-crew-remote-worker}"
: "${CREW_REMOTE_REPO:?}" "${CREW_REMOTE_IMAGE:?}" "${CREW_REMOTE_WORKER_COMMAND:?}"
CODE="${CREW_REMOTE_CODE:-}"
TYPES="${CREW_REMOTE_TYPES:-c7a.8xlarge m7a.8xlarge r7a.8xlarge}"
NAME="crew-remote-workers-$RUN_NAME"
here="$(cd "$(dirname "$0")" && pwd)"

## the user data, filled in
fill() {
  local text
  text=$(cat "$1")
  shift
  while [ $# -gt 0 ]; do text=${text//"$1"/"$2"}; shift 2; done
  printf '%s\n' "$text"
}
with_helpers=$(mktemp)
awk -v helpers="$here/helpers.sh" '
  /^# crew.remote: (boss )?helpers/ { while ((getline line < helpers) > 0) print line; next }
  { print }
' "$here/worker-data.sh" > "$with_helpers"
user_data=$(fill "$with_helpers" \
  __RUN_FOLDER__ "s3://$CREW_REMOTE_BUCKET/$RUN_NAME" \
  __BUCKET_REGION__ "$CREW_REMOTE_BUCKET_REGION" \
  __REPO__ "$CREW_REMOTE_REPO" \
  __CODE__ "$CODE" \
  __IMAGE__ "$CREW_REMOTE_IMAGE" \
  __WORKER_COMMAND__ "$CREW_REMOTE_WORKER_COMMAND" \
  __DOCKER_OPTIONS__ "${CREW_REMOTE_DOCKER_OPTIONS:-}" \
  __CALL_FILE__ "${CREW_REMOTE_CALL_FILE:-cache/remote/worker_call.R}" \
  __MAX_HOURS__ "$HOURS" | base64 | tr -d '\n')
rm -f "$with_helpers"

## the workers' security group in the default network: no inbound rules
vpc=$(aws ec2 describe-vpcs --region "$REGION" --filters Name=is-default,Values=true \
  --query 'Vpcs[0].VpcId' --output text)
group=$(aws ec2 describe-security-groups --region "$REGION" \
  --filters "Name=group-name,Values=crew-remote-workers" "Name=vpc-id,Values=$vpc" \
  --query 'SecurityGroups[0].GroupId' --output text)
if [ "$group" = "None" ]; then
  group=$(aws ec2 create-security-group --region "$REGION" --vpc-id "$vpc" \
    --group-name crew-remote-workers --description "crew.remote workers: no inbound, they only dial out" \
    --query GroupId --output text)
fi

## the launch template: Amazon Linux 2023, the role, a 40 GB disk,
## terminate on shutdown, and the tag by which the boss finds the machines
image=$(aws ssm get-parameter --region "$REGION" \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query Parameter.Value --output text)
template_data="{
    \"ImageId\": \"$image\",
    \"IamInstanceProfile\": {\"Name\": \"$CREW_REMOTE_WORKER_ROLE\"},
    \"UserData\": \"$user_data\",
    \"InstanceInitiatedShutdownBehavior\": \"terminate\",
    \"BlockDeviceMappings\": [{\"DeviceName\": \"/dev/xvda\",
      \"Ebs\": {\"VolumeSize\": 40, \"VolumeType\": \"gp3\", \"DeleteOnTermination\": true, \"Encrypted\": true}}],
    \"SecurityGroupIds\": [\"$group\"],
    \"MetadataOptions\": {\"HttpTokens\": \"required\"},
    \"TagSpecifications\": [{\"ResourceType\": \"instance\",
      \"Tags\": [{\"Key\": \"crew-remote-run\", \"Value\": \"$RUN_NAME\"},
                 {\"Key\": \"Name\", \"Value\": \"$NAME\"}]}]
  }"
# a new version if the run has its template already (a second fleet, or a relaunch)
if aws ec2 describe-launch-templates --region "$REGION" --launch-template-names "$NAME" > /dev/null 2>&1; then
  aws ec2 create-launch-template-version --region "$REGION" --launch-template-name "$NAME" \
    --launch-template-data "$template_data" > /dev/null
else
  aws ec2 create-launch-template --region "$REGION" --launch-template-name "$NAME" \
    --launch-template-data "$template_data" > /dev/null
fi

## every type in every subnet of the default network, so the fleet can take
## whatever spot capacity there is
subnets=$(aws ec2 describe-subnets --region "$REGION" --filters "Name=vpc-id,Values=$vpc" \
  --query 'Subnets[].SubnetId' --output text)
overrides=""
for type in $TYPES; do
  for subnet in $subnets; do
    overrides="$overrides{\"InstanceType\": \"$type\", \"SubnetId\": \"$subnet\"},"
  done
done

## the fleet
spot_options="AllocationStrategy=price-capacity-optimized"
if [ "${CREW_REMOTE_CAPACITY_REBALANCE:-0}" = "1" ]; then
  spot_options="$spot_options,MaintenanceStrategies={CapacityRebalance={ReplacementStrategy=launch}}"
fi
until=$(date -u -v+"${HOURS}"H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null ||
        date -u -d "+$HOURS hours" +%Y-%m-%dT%H:%M:%SZ)
aws ec2 create-fleet --region "$REGION" \
  --type maintain \
  --valid-until "$until" \
  --terminate-instances-with-expiration \
  --target-capacity-specification "TotalTargetCapacity=$MACHINES,DefaultTargetCapacityType=spot" \
  --spot-options "$spot_options" \
  --launch-template-configs "[{\"LaunchTemplateSpecification\": {\"LaunchTemplateName\": \"$NAME\", \"Version\": \"\$Latest\"},
                               \"Overrides\": [${overrides%,}]}]" \
  --tag-specifications "ResourceType=fleet,Tags=[{Key=crew-remote-run,Value=$RUN_NAME}]" \
  --query FleetId --output text
