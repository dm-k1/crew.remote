#!/bin/bash
## =====================================================================
##  The boss of the AWS test (user data; aws-test/run.sh fills it in): runs
##  aws-test/_targets.R in rocker/r-ver, with workers in WORKER_REGIONS, and
##  writes the tasks' table to S3. Uses the helpers launch_boss.sh puts in.
## =====================================================================
RUN_FOLDER="__RUN_FOLDER__"
RUN_NAME="__RUN_NAME__"
BUCKET_REGION="__BUCKET_REGION__"
CODE="__CODE__"
WORKER_REGIONS="__WORKER_REGIONS__"
IMAGE="rocker/r-ver:4.6.1"
PORT=5555
exec > /var/log/crew-remote-test.log 2>&1
set -x
export AWS_DEFAULT_REGION="$BUCKET_REGION"
shutdown -h +90

# crew.remote: boss helpers

finish() {
  crew_remote_stop_workers "$RUN_FOLDER" "$RUN_NAME" "$WORKER_REGIONS"
  aws s3 cp /var/log/crew-remote-test.log "$RUN_FOLDER/boss.log" --only-show-errors
  shutdown -h now
}
trap finish EXIT

dnf install -y docker git
systemctl start docker
git clone https://github.com/dm-k1/crew.remote.git /opt/project
cd /opt/project && git checkout "$CODE" && git log --oneline -1
aws s3 rm "$RUN_FOLDER/done" --only-show-errors || true
while true; do
  crew_remote_publish_call aws-test/cache/remote/worker_call.R "$RUN_FOLDER"
  crew_remote_let_workers_in "$PORT" "$RUN_NAME" "$WORKER_REGIONS"
  sleep 20
done > /var/log/crew-remote-access.log 2>&1 &

docker run --rm --network host -v /opt/project:/project -w /project \
  -e CREW_REMOTE_ADDRESS="$(crew_remote_metadata public-ipv4)" "$IMAGE" Rscript -e '
    source("aws-test/setup.R")
    setwd("aws-test")
    started <- Sys.time()
    targets::tar_make()
    tasks <- targets::tar_read(tasks)
    meta <- targets::tar_meta(fields = c("name", "error"))
    cat(sprintf("TASKS DONE: %d of 60 in %.1f minutes\n", nrow(tasks),
                as.numeric(difftime(Sys.time(), started, units = "mins"))))
    print(table(tasks$region, tasks$host))
    write.csv(tasks, "tasks.csv", row.names = FALSE)
  '
echo "pipeline exited with status $?"
aws s3 cp aws-test/tasks.csv "$RUN_FOLDER/tasks.csv" --only-show-errors
