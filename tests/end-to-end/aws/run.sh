#!/bin/bash
## =====================================================================
##  crew.remote's end-to-end test on AWS: a boss and one spot fleet per
##  worker region run ../pipeline/_targets.R (TASKS tasks of TASK_SECONDS,
##  default 60 of 30 s). Afterwards ../check.R, with RUN_FOLDER set, checks
##  the outcome from S3.
##
##    tests/end-to-end/aws/run.sh <run name> <commit> <boss region> "<worker regions>" [--boss-only]
##
##  --boss-only: a new boss for a run whose boss was lost (terminate the old
##  one first); it continues from the run's store in S3, and the time of the
##  restart is written to S3 for the checks.
##
##  Settings as for inst/aws: CREW_REMOTE_BUCKET and CREW_REMOTE_BUCKET_REGION
##  (the roles are those of inst/aws/setup.sh unless CREW_REMOTE_BOSS_ROLE or
##  CREW_REMOTE_WORKER_ROLE say otherwise). The machines are small
##  burstable ones (2 vCPUs: the boss on-demand t3.small, about $0.02 an hour;
##  workers spot t3/t3a small or medium, 2 workers each), as the tasks only
##  wait: a run costs a few cents. Other types: CREW_REMOTE_BOSS_TYPE,
##  CREW_REMOTE_TYPES. Every machine uses the test image of <commit>
##  (ghcr.io/dm-k1/crew.remote-test:sha-<commit>, built by GitHub Actions for
##  every commit on main), so nothing is installed at start. Test changes
##  without AWS first (../local).
## =====================================================================
set -euo pipefail
RUN_NAME="$1"
CODE="$2"
BOSS_REGION="$3"
WORKER_REGIONS="$4"
BOSS_ONLY="${5:-}"
here="$(cd "$(dirname "$0")" && pwd)"
aws_scripts="$here/../../../inst/aws"
folder="s3://$CREW_REMOTE_BUCKET/$RUN_NAME"
image="ghcr.io/dm-k1/crew.remote-test:sha-${CODE:0:7}"

## the boss
if [ "$BOSS_ONLY" = "--boss-only" ]; then
  date -u +%Y-%m-%dT%H:%M:%S | aws s3 cp - "$folder/restarted_at.txt" --region "$CREW_REMOTE_BUCKET_REGION"
fi
boss_data=$(mktemp)
text=$(cat "$here/boss-data.sh")
for pair in "__RUN_FOLDER__=$folder" "__RUN_NAME__=$RUN_NAME" "__BUCKET_REGION__=$CREW_REMOTE_BUCKET_REGION" \
            "__CODE__=$CODE" "__WORKER_REGIONS__=$WORKER_REGIONS" "__IMAGE__=$image"; do
  text=${text//"${pair%%=*}"/"${pair#*=}"}
done
printf '%s\n' "$text" > "$boss_data"
echo "boss: $("$aws_scripts/launch_boss.sh" "$BOSS_REGION" "$RUN_NAME" "$boss_data" "${CREW_REMOTE_BOSS_TYPE:-t3.small}")"
rm -f "$boss_data"
[ "$BOSS_ONLY" = "--boss-only" ] && exit 0

## the workers, one fleet per region
export CREW_REMOTE_REPO="https://github.com/dm-k1/crew.remote.git"
export CREW_REMOTE_CODE="$CODE"
export CREW_REMOTE_IMAGE="$image"
export CREW_REMOTE_WORKER_COMMAND="Rscript tests/end-to-end/aws/worker.R"
export CREW_REMOTE_CALL_FILE="cache/remote/worker_call.R"
export CREW_REMOTE_TYPES="${CREW_REMOTE_TYPES:-t3.small t3a.small t3.medium t3a.medium}"
for region in $WORKER_REGIONS; do
  echo "workers ($region): $("$aws_scripts/launch_workers.sh" "$region" 1 "$RUN_NAME" 2)"
done
