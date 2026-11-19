#!/bin/bash
## =====================================================================
##  crew.remote: remove what setup.sh and past runs left on AWS (unofficial;
##  not part of crew)
##
##    inst/aws/teardown.sh "<regions>"
##
##  In each region: the launch templates crew-remote-workers-*, the boss
##  security groups crew-remote-boss-*, the workers' security group
##  crew-remote-workers and the Fault Injection Service experiment templates
##  tagged crew-remote. Then the three roles and their instance profiles
##  (names as in setup.sh). Refuses while a run's fleet or machine is still
##  going. Does not touch S3: a run's results and logs stay in the bucket.
## =====================================================================
set -euo pipefail
REGIONS="$1"
BOSS="${CREW_REMOTE_BOSS_ROLE:-crew-remote-boss}"
WORKER="${CREW_REMOTE_WORKER_ROLE:-crew-remote-worker}"
FIS="crew-remote-fis"

## nothing may still be running
for region in $REGIONS; do
  busy=$(aws ec2 describe-instances --region "$region" \
    --filters "Name=tag-key,Values=crew-remote-run,crew-remote-boss" "Name=instance-state-name,Values=pending,running" \
    --query 'Reservations[].Instances[].InstanceId' --output text)
  fleets=$(aws ec2 describe-fleets --region "$region" \
    --query "Fleets[?FleetState=='active' && Tags[?Key=='crew-remote-run']].FleetId" --output text)
  if [ -n "$busy$fleets" ]; then
    echo "$region still has a run going ($busy $fleets): stop it first"
    exit 1
  fi
done

for region in $REGIONS; do
  for template in $(aws ec2 describe-launch-templates --region "$region" \
      --query "LaunchTemplates[?starts_with(LaunchTemplateName, 'crew-remote-workers-')].LaunchTemplateName" --output text); do
    aws ec2 delete-launch-template --region "$region" --launch-template-name "$template" > /dev/null
    echo "$region: deleted launch template $template"
  done
  for group in $(aws ec2 describe-security-groups --region "$region" \
      --filters "Name=group-name,Values=crew-remote-boss-*,crew-remote-workers" \
      --query 'SecurityGroups[].GroupId' --output text); do
    aws ec2 delete-security-group --region "$region" --group-id "$group" > /dev/null
    echo "$region: deleted security group $group"
  done
  for experiment in $(aws fis list-experiment-templates --region "$region" \
      --query "experimentTemplates[?tags.\"crew-remote\"].id" --output text); do
    aws fis delete-experiment-template --region "$region" --id "$experiment" > /dev/null
    echo "$region: deleted experiment template $experiment"
  done
done

## the roles and instance profiles
for name in "$BOSS" "$WORKER" "$FIS"; do
  aws iam get-role --role-name "$name" > /dev/null 2>&1 || continue
  if aws iam get-instance-profile --instance-profile-name "$name" > /dev/null 2>&1; then
    aws iam remove-role-from-instance-profile --instance-profile-name "$name" --role-name "$name" 2>/dev/null || true
    aws iam delete-instance-profile --instance-profile-name "$name"
  fi
  for policy in $(aws iam list-role-policies --role-name "$name" --query 'PolicyNames[]' --output text); do
    aws iam delete-role-policy --role-name "$name" --policy-name "$policy"
  done
  for arn in $(aws iam list-attached-role-policies --role-name "$name" --query 'AttachedPolicies[].PolicyArn' --output text); do
    aws iam detach-role-policy --role-name "$name" --policy-arn "$arn"
  done
  aws iam delete-role --role-name "$name"
  echo "deleted role $name"
done
