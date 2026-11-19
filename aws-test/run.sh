#!/bin/bash
## =====================================================================
##  crew.remote's test on AWS: a boss and one spot fleet per worker region
##  run aws-test/_targets.R (60 tasks of 30 seconds); afterwards
##  s3://<bucket>/<run name>/tasks.csv says which machine and region ran
##  each task, and boss.log how it went.
##
##    aws-test/run.sh <run name> <commit of crew.remote> <boss region> "<worker regions>"
##
##  Settings as for inst/aws (CREW_REMOTE_BUCKET, CREW_REMOTE_BUCKET_REGION,
##  CREW_REMOTE_BOSS_ROLE, CREW_REMOTE_WORKER_ROLE). The machines are small
##  burstable ones (2 vCPUs: the boss on-demand t3.small, about $0.02 an hour;
##  workers spot t3/t3a small or medium, 2 workers each), as the tasks only
##  wait: a run costs a few cents. Other types: CREW_REMOTE_BOSS_TYPE,
##  CREW_REMOTE_TYPES. The logic is tested without AWS in local-test/.
## =====================================================================
set -euo pipefail
RUN_NAME="$1"
CODE="$2"
BOSS_REGION="$3"
WORKER_REGIONS="$4"
here="$(cd "$(dirname "$0")" && pwd)"
aws_scripts="$here/../inst/aws"
folder="s3://$CREW_REMOTE_BUCKET/$RUN_NAME"

boss_data=$(mktemp)
text=$(cat "$here/boss-data.sh")
for pair in "__RUN_FOLDER__=$folder" "__RUN_NAME__=$RUN_NAME" "__BUCKET_REGION__=$CREW_REMOTE_BUCKET_REGION" \
            "__CODE__=$CODE" "__WORKER_REGIONS__=$WORKER_REGIONS"; do
  text=${text//"${pair%%=*}"/"${pair#*=}"}
done
printf '%s\n' "$text" > "$boss_data"
echo "boss: $("$aws_scripts/launch_boss.sh" "$BOSS_REGION" "$RUN_NAME" "$boss_data" "${CREW_REMOTE_BOSS_TYPE:-t3.small}")"
rm -f "$boss_data"

export CREW_REMOTE_REPO="https://github.com/dm-k1/crew.remote.git"
export CREW_REMOTE_CODE="$CODE"
export CREW_REMOTE_IMAGE="rocker/r-ver:4.6.1"
export CREW_REMOTE_WORKER_COMMAND="Rscript aws-test/worker.R"
export CREW_REMOTE_CALL_FILE="cache/remote/worker_call.R"
export CREW_REMOTE_TYPES="${CREW_REMOTE_TYPES:-t3.small t3a.small t3.medium t3a.medium}"
for region in $WORKER_REGIONS; do
  echo "workers ($region): $("$aws_scripts/launch_workers.sh" "$region" 1 "$RUN_NAME" 2)"
done
