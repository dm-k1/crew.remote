#!/bin/bash
## =====================================================================
##  crew.remote: a worker machine on AWS (Amazon Linux 2023), as user
##  data; launch_workers.sh fills it in (unofficial; not part of crew).
##
##  Gets the project (a git repository at a commit, or an s3:// .tar.gz),
##  starts the project's worker command in its Docker image (on the host's
##  network, to reach the boss), and every 20 seconds copies the worker
##  command from S3 to the call file, so after a restart of the boss
##  elsewhere the workers find it again. When "done" appears in S3, or AWS
##  gives notice that it takes the machine back (two minutes ahead), copies
##  its logs to S3 and shuts down (launched to terminate on shutdown). If the
##  workers stop by themselves (their setup failed, say too little memory),
##  it copies its logs and stays up, idle, until the safety cutoff: shutting
##  down would make the fleet start another machine that fails the same way.
##  Either way, why it stopped is in <run folder>/worker-stops/<machine>.txt. A
##  safety cutoff shuts it down after MAX_HOURS whatever happens.
## =====================================================================
RUN_FOLDER="__RUN_FOLDER__"
BUCKET_REGION="__BUCKET_REGION__"
REPO="__REPO__"
CODE="__CODE__"
IMAGE="__IMAGE__"
WORKER_COMMAND="__WORKER_COMMAND__"
DOCKER_OPTIONS="__DOCKER_OPTIONS__"
CALL_FILE="__CALL_FILE__"
MAX_HOURS="__MAX_HOURS__"

LOG=/var/log/crew-remote-worker.log
exec > "$LOG" 2>&1
set -x
[ -n "$BUCKET_REGION" ] && export AWS_DEFAULT_REGION="$BUCKET_REGION"
shutdown -h "+$((MAX_HOURS * 60))"

# crew.remote: helpers

## at the end: this machine's logs to S3 (one folder per machine)
copy_logs() {
  cd /opt/project 2>/dev/null || true
  machine=$(crew_remote_metadata instance-id)
  aws s3 sync cache/logs "$RUN_FOLDER/worker-logs/$machine" --only-show-errors || true
  aws s3 cp "$LOG" "$RUN_FOLDER/worker-logs/$machine/machine.log" --only-show-errors || true
}
## if the script stops early (a failed install, say): logs, then shut down
trap 'copy_logs; shutdown -h now' EXIT

## Docker, git and the project
dnf install -y docker git
systemctl start docker
case "$CODE" in
  s3://*)
    mkdir -p /opt/project
    aws s3 cp "$CODE" /tmp/code.tar.gz --only-show-errors
    tar -xzf /tmp/code.tar.gz -C /opt/project
    cd /opt/project || exit 1
    ;;
  *)
    git clone "$REPO" /opt/project
    cd /opt/project || exit 1
    [ -n "$CODE" ] && git checkout "$CODE"
    git log --oneline -1
    ;;
esac
docker pull "$IMAGE"
mkdir -p "$(dirname "$CALL_FILE")"

## the workers
echo "cores: $(nproc)"
# shellcheck disable=SC2086  # DOCKER_OPTIONS and WORKER_COMMAND are lists of words
docker run -d --name worker --network host -v "$PWD":/project -w /project $DOCKER_OPTIONS \
  "$IMAGE" $WORKER_COMMAND

## every 20 seconds: the boss's command, fresh from S3; stop when the run is
## done or AWS takes the machine back (its running tasks are then lost, and
## the boss hands them out again)
crew_remote_workers_running() { docker ps -q --filter name=worker | grep -q .; }
why=$(crew_remote_watch "$RUN_FOLDER" "$CALL_FILE")
echo "stopping: $why"
docker logs worker 2>&1 | tail -50
docker stop -t 30 worker || true
trap - EXIT
copy_logs
crew_remote_report_stop "$RUN_FOLDER" "$(crew_remote_metadata instance-id)" "$why"
if [ "$why" = "the workers stopped" ]; then
  echo "the workers stopped by themselves: staying up, idle, until the safety cutoff"
  sleep infinity
fi
shutdown -h now
