#!/bin/bash
## =====================================================================
##  crew.remote: the boss machine on AWS, one on-demand EC2 instance
##  (unofficial; not part of crew)
##
##    launch_boss.sh <region> <run name> <user data file> [instance type]
##
##  The user data file is the project's own script for the boss (it runs the
##  pipeline with crew_controller_remote()). Where it has the line
##  "# crew.remote: helpers" (or "# crew.remote: boss helpers"), the
##  functions of helpers.sh are put in, for it to call. On-demand, so AWS does not take it back.
##
##  Settings, as environment variables: CREW_REMOTE_BOSS_ROLE (default
##  crew-remote-boss, made by setup.sh), an instance profile that may use the bucket, see the run's instances and fleets,
##  change security groups tagged crew-remote-role = boss and delete fleets
##  tagged crew-remote-run (boss-policy.json).
##
##  Its disk is encrypted and it requires IMDSv2. Its security group
##  (crew-remote-boss-<run name>) starts closed; the boss
##  opens the workers' port to its own worker machines only
##  (crew_remote_let_workers_in). Needs the AWS command line tool, logged in.
## =====================================================================
set -euo pipefail
REGION="$1"
RUN_NAME="$2"
USER_DATA="$3"
TYPE="${4:-m7a.large}"
CREW_REMOTE_BOSS_ROLE="${CREW_REMOTE_BOSS_ROLE:-crew-remote-boss}"
NAME="crew-remote-boss-$RUN_NAME"
here="$(cd "$(dirname "$0")" && pwd)"

## the user data with the helpers put in
filled=$(mktemp)
awk -v helpers="$here/helpers.sh" '
  /^# crew.remote: (boss )?helpers/ { while ((getline line < helpers) > 0) print line; next }
  { print }
' "$USER_DATA" > "$filled"

## its security group, in the default network, tagged so the boss may change it
vpc=$(aws ec2 describe-vpcs --region "$REGION" --filters Name=is-default,Values=true \
  --query 'Vpcs[0].VpcId' --output text)
group=$(aws ec2 describe-security-groups --region "$REGION" \
  --filters "Name=group-name,Values=$NAME" "Name=vpc-id,Values=$vpc" \
  --query 'SecurityGroups[0].GroupId' --output text)
if [ "$group" = "None" ]; then
  group=$(aws ec2 create-security-group --region "$REGION" --vpc-id "$vpc" \
    --group-name "$NAME" --description "crew.remote boss of run $RUN_NAME: the workers port, opened by the boss" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=crew-remote-role,Value=boss},{Key=crew-remote-run,Value=$RUN_NAME}]" \
    --query GroupId --output text)
fi

## the instance
image=$(aws ssm get-parameter --region "$REGION" \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query Parameter.Value --output text)
aws ec2 run-instances --region "$REGION" \
  --image-id "$image" --instance-type "$TYPE" --count 1 \
  --iam-instance-profile "Name=$CREW_REMOTE_BOSS_ROLE" \
  --security-group-ids "$group" \
  --instance-initiated-shutdown-behavior terminate \
  --metadata-options HttpTokens=required \
  --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=40,VolumeType=gp3,DeleteOnTermination=true,Encrypted=true}' \
  --user-data "file://$filled" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME},{Key=crew-remote-boss,Value=$RUN_NAME}]" \
  --query 'Instances[0].InstanceId' --output text
rm -f "$filled"
