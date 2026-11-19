#!/bin/bash
## A worker "machine" of the local test, as inst/aws/worker-data.sh on AWS but
## without Docker: crew.remote's workers (two), the worker command kept fresh
## from S3 by crew_remote_watch, and the logs and why it stopped to S3.
## BREAK_SETUP=1: its setup fails at once (a machine with a broken setup)
source inst/aws/helpers.sh
mkdir -p cache/remote cache/logs/workers
until aws s3 ls s3://crew-remote-test > /dev/null 2>&1; do sleep 1; done # the boss makes the bucket
if [ "${BREAK_SETUP:-0}" = "1" ]; then
  Rscript -e 'stop("this machine'"'"'s setup failed (on purpose, for the test)")' &
else
  Rscript -e 'crew.remote::crew_remote_worker("cache/remote/worker_call.R", workers = 2)' &
fi
worker=$!
crew_remote_workers_running() { kill -0 "$worker" 2> /dev/null; }
why=$(crew_remote_watch "$RUN_FOLDER" cache/remote/worker_call.R)
echo "$HOSTNAME stops: $why"
pkill -TERM -P "$worker"; kill -TERM "$worker"
aws s3 sync cache/logs "$RUN_FOLDER/worker-logs/$HOSTNAME" --only-show-errors
crew_remote_report_stop "$RUN_FOLDER" "$HOSTNAME" "$why"
sleep infinity # a stopped machine; the test ends with the boss
