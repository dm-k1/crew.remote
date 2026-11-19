#!/bin/bash
## A worker "machine" of the local test, as inst/aws/worker-data.sh on AWS but
## without Docker: crew.remote's workers (two), the worker command kept fresh
## from S3 by crew_remote_watch, and the logs to S3 when it stops
source inst/aws/helpers.sh
mkdir -p cache/remote cache/logs/workers
Rscript -e 'crew.remote::crew_remote_worker("cache/remote/worker_call.R", workers = 2)' &
worker=$!
crew_remote_workers_running() { kill -0 "$worker" 2> /dev/null; }
why=$(crew_remote_watch "$RUN_FOLDER" cache/remote/worker_call.R)
echo "$HOSTNAME stops: $why" | tee cache/logs/workers/stopped.txt
pkill -TERM -P "$worker"; kill -TERM "$worker"
aws s3 sync cache/logs "$RUN_FOLDER/worker-logs/$HOSTNAME" --only-show-errors
sleep infinity # a stopped machine; the test ends with the boss
