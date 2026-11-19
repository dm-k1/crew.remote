#!/bin/bash
## =====================================================================
##  The boss of the AWS end-to-end test (user data; run.sh fills it in):
##  runs ../pipeline/_targets.R in rocker/r-ver with workers in
##  WORKER_REGIONS, and writes tasks.csv to S3. Uses the helpers
##  inst/aws/launch_boss.sh puts in. Keeps the pipeline's store in S3 and
##  starts from it, so a boss that is lost can be replaced (run.sh
##  --boss-only); it stops the workers only after a successful run.
## =====================================================================
RUN_FOLDER="__RUN_FOLDER__"
RUN_NAME="__RUN_NAME__"
BUCKET_REGION="__BUCKET_REGION__"
CODE="__CODE__"
WORKER_REGIONS="__WORKER_REGIONS__"
IMAGE="rocker/r-ver:4.6.1"
PORT=5555
LOG=/var/log/crew-remote-test.log
exec > "$LOG" 2>&1
set -x
export AWS_DEFAULT_REGION="$BUCKET_REGION"
shutdown -h +90

# crew.remote: helpers

status=1
finish() {
  [ "$status" = "0" ] && crew_remote_stop_workers "$RUN_FOLDER" "$RUN_NAME" "$WORKER_REGIONS"
  aws s3 cp "$LOG" "$RUN_FOLDER/boss.log" --only-show-errors
  shutdown -h now
}
trap finish EXIT

dnf install -y docker git
systemctl start docker
git clone https://github.com/dm-k1/crew.remote.git /opt/project
cd /opt/project && git checkout "$CODE" && git log --oneline -1
pipeline=tests/end-to-end/pipeline
store=(--exclude "meta/process" --exclude "scratch/*" --only-show-errors)
aws s3 sync "$RUN_FOLDER/store" "$pipeline/_targets" "${store[@]}"
aws s3 rm "$RUN_FOLDER/done" --only-show-errors || true
while true; do
  crew_remote_publish_call "$pipeline/cache/remote/worker_call.R" "$RUN_FOLDER"
  crew_remote_let_workers_in "$PORT" "$RUN_NAME" "$WORKER_REGIONS"
  aws s3 sync "$pipeline/_targets" "$RUN_FOLDER/store" "${store[@]}"
  sleep 20
done > /var/log/crew-remote-access.log 2>&1 &

docker run --rm --network host -v /opt/project:/project -w /project \
  -e CREW_REMOTE_ADDRESS="$(crew_remote_metadata public-ipv4)" "$IMAGE" Rscript -e '
    source("tests/end-to-end/aws/setup.R")
    setwd("tests/end-to-end/pipeline")
    targets::tar_make()
    write.csv(targets::tar_read(tasks), "tasks.csv", row.names = FALSE)
  '
status=$?
echo "pipeline exited with status $status"
aws s3 cp "$pipeline/tasks.csv" "$RUN_FOLDER/tasks.csv" --only-show-errors
