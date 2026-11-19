#!/bin/bash
## The boss of the local test: the pipeline (../pipeline/_targets.R), the
## worker command published to S3 with crew.remote's helper, its results to
## S3, "done" at the end, then the checks (../check.R). Partway through, the
## boss is lost (every R process killed) and comes back under another address
## (boss-again), as a new boss machine would.
set -x
source inst/aws/helpers.sh
until aws s3 mb s3://crew-remote-test 2>/dev/null || aws s3 ls s3://crew-remote-test > /dev/null 2>&1; do sleep 1; done
pipeline=tests/end-to-end/pipeline
while true; do crew_remote_publish_call "$pipeline/cache/remote/worker_call.R" "$RUN_FOLDER"; sleep 2; done &
cd "$pipeline" || exit 1

# the first boss, lost after 30 seconds
CREW_REMOTE_ADDRESS=boss Rscript -e 'targets::tar_make()' &
sleep 30
pkill -KILL -x R
sleep 2
date -u +%Y-%m-%dT%H:%M:%S | aws s3 cp - "$RUN_FOLDER/restarted_at.txt"

# the new boss, elsewhere
CREW_REMOTE_ADDRESS=boss-again Rscript -e '
  targets::tar_make()
  write.csv(targets::tar_read(tasks), "tasks.csv", row.names = FALSE)
'
aws s3 cp tasks.csv "$RUN_FOLDER/tasks.csv"
cd - > /dev/null || exit 1
echo done | aws s3 cp - "$RUN_FOLDER/done"
sleep 20 # the workers copy their logs
Rscript tests/end-to-end/check.R
