#!/bin/bash
## =====================================================================
##  A real spot interruption for the AWS end-to-end test: AWS Fault
##  Injection Service gives one running worker machine of the run (tag
##  crew-remote-run) AWS's two-minute notice, then takes it back.
##
##    tests/end-to-end/aws/interrupt.sh <region> <run name>
##
##  Needs the role crew-remote-fis (inst/aws/setup.sh). The experiment
##  template is tagged crew-remote, so inst/aws/teardown.sh removes it.
##  Afterwards, check with EXPECT_SPOT=1 (../check.R).
## =====================================================================
set -euo pipefail
REGION="$1"
RUN_NAME="$2"
account=$(aws sts get-caller-identity --query Account --output text)
template=$(aws fis create-experiment-template --region "$REGION" --cli-input-json "{
  \"description\": \"crew.remote test: interrupt one spot worker machine of run $RUN_NAME\",
  \"roleArn\": \"arn:aws:iam::$account:role/crew-remote-fis\",
  \"stopConditions\": [{\"source\": \"none\"}],
  \"targets\": {\"worker\": {
    \"resourceType\": \"aws:ec2:spot-instance\",
    \"resourceTags\": {\"crew-remote-run\": \"$RUN_NAME\"},
    \"filters\": [{\"path\": \"State.Name\", \"values\": [\"running\"]}],
    \"selectionMode\": \"COUNT(1)\"}},
  \"actions\": {\"interrupt\": {
    \"actionId\": \"aws:ec2:send-spot-instance-interruptions\",
    \"parameters\": {\"durationBeforeInterruption\": \"PT2M\"},
    \"targets\": {\"SpotInstances\": \"worker\"}}},
  \"tags\": {\"crew-remote\": \"$RUN_NAME\"}
}" --query experimentTemplate.id --output text)
aws fis start-experiment --region "$REGION" --experiment-template-id "$template" \
  --query 'experiment.[id,state.status]' --output text
