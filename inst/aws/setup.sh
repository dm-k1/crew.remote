#!/bin/bash
## =====================================================================
##  crew.remote: the AWS roles, once per account (unofficial; not part of crew)
##
##    CREW_REMOTE_BUCKET=<bucket> inst/aws/setup.sh
##
##  Creates (or updates) three IAM roles, with the least privilege the scripts
##  need:
##    boss    (CREW_REMOTE_BOSS_ROLE, default crew-remote-boss): the bucket;
##            see the run's instances and fleets; change only security groups
##            tagged crew-remote-role = boss; delete only fleets tagged
##            crew-remote-run (boss-policy.json); Systems Manager, to get in
##            without SSH
##    workers (CREW_REMOTE_WORKER_ROLE, default crew-remote-worker): read the
##            bucket; write only worker-logs/ and worker-stops/ (worker-policy.json)
##    fis     (crew-remote-fis): lets AWS Fault Injection Service send test spot
##            interruptions (AWS's managed policy for EC2 experiments)
##  The boss and workers get instance profiles of the same name. teardown.sh
##  removes it all again. Needs the AWS command line tool, logged in.
## =====================================================================
set -euo pipefail
: "${CREW_REMOTE_BUCKET:?set CREW_REMOTE_BUCKET to the run bucket}"
BOSS="${CREW_REMOTE_BOSS_ROLE:-crew-remote-boss}"
WORKER="${CREW_REMOTE_WORKER_ROLE:-crew-remote-worker}"
FIS="crew-remote-fis"
here="$(cd "$(dirname "$0")" && pwd)"

trust() { printf '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"%s"},"Action":"sts:AssumeRole"}]}' "$1"; }

## a role (if it does not exist yet) with an inline policy and/or managed policies
role() {
  local name="$1" service="$2" policy_file="$3"; shift 3
  if ! aws iam get-role --role-name "$name" > /dev/null 2>&1; then
    aws iam create-role --role-name "$name" --assume-role-policy-document "$(trust "$service")" \
      --tags Key=crew-remote,Value=role > /dev/null
    echo "created role $name"
  fi
  if [ -n "$policy_file" ]; then
    aws iam put-role-policy --role-name "$name" --policy-name crew-remote \
      --policy-document "$(sed "s/__BUCKET__/$CREW_REMOTE_BUCKET/g" "$policy_file")"
  fi
  for managed in "$@"; do
    aws iam attach-role-policy --role-name "$name" --policy-arn "$managed"
  done
}

## an instance profile of the same name, holding the role
profile() {
  local name="$1"
  if ! aws iam get-instance-profile --instance-profile-name "$name" > /dev/null 2>&1; then
    aws iam create-instance-profile --instance-profile-name "$name" > /dev/null
    aws iam add-role-to-instance-profile --instance-profile-name "$name" --role-name "$name"
    echo "created instance profile $name"
  fi
}

role "$BOSS" ec2.amazonaws.com "$here/boss-policy.json" \
  arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
profile "$BOSS"
role "$WORKER" ec2.amazonaws.com "$here/worker-policy.json"
profile "$WORKER"
role "$FIS" fis.amazonaws.com "" \
  arn:aws:iam::aws:policy/service-role/AWSFaultInjectionSimulatorEC2Access
echo "roles ready: boss $BOSS, workers $WORKER, fault injection $FIS"
