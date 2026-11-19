#!/bin/bash
## The boss of the local test: the pipeline (aws-test/_targets.R), the worker
## command published to S3 with crew.remote's helper, "done" at the end, then
## the checks (local-test/check.R)
set -x
source inst/aws/helpers.sh
until aws s3 mb s3://crew-remote-test 2>/dev/null || aws s3 ls s3://crew-remote-test > /dev/null 2>&1; do sleep 1; done
while true; do crew_remote_publish_call aws-test/cache/remote/worker_call.R "$RUN_FOLDER"; sleep 2; done &
(cd aws-test && Rscript -e '
  targets::tar_make()
  write.csv(targets::tar_read(tasks), "tasks.csv", row.names = FALSE)
')
echo done | aws s3 cp - "$RUN_FOLDER/done"
sleep 20 # the workers copy their logs
Rscript local-test/check.R
