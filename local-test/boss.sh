#!/bin/bash
## The boss of the local test: the pipeline (aws-test/_targets.R), the worker
## command published to S3 with crew.remote's helper, "done" at the end, then
## the checks (local-test/check.R). Partway through, the boss is lost (its
## pipeline killed) and comes back under another address (boss-again), as a
## new boss machine would: the workers must find it through the new command
## in S3, and the tasks finished before must stay finished.
set -x
source inst/aws/helpers.sh
until aws s3 mb s3://crew-remote-test 2>/dev/null || aws s3 ls s3://crew-remote-test > /dev/null 2>&1; do sleep 1; done
while true; do crew_remote_publish_call aws-test/cache/remote/worker_call.R "$RUN_FOLDER"; sleep 2; done &
cd aws-test || exit 1

# the first boss, lost after 30 seconds: every R process of this "machine"
# killed at once, as when a machine is lost
CREW_REMOTE_ADDRESS=boss Rscript -e 'targets::tar_make()' &
sleep 30
pkill -KILL -x R
sleep 2
date -u +%Y-%m-%dT%H:%M:%S > restarted_at.txt
Rscript -e 'cat("tasks finished before the restart:", sum(targets::tar_progress()$progress == "completed"), "\n")'

# the new boss, elsewhere
CREW_REMOTE_ADDRESS=boss-again Rscript -e '
  targets::tar_make()
  write.csv(targets::tar_read(tasks), "tasks.csv", row.names = FALSE)
'
cd ..
echo done | aws s3 cp - "$RUN_FOLDER/done"
sleep 20 # the workers copy their logs
Rscript local-test/check.R
