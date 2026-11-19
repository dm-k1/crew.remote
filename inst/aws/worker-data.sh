#!/bin/bash
## =====================================================================
##  crew.remote: a worker machine on AWS (Amazon Linux 2023), as user
##  data; launch_workers.sh fills it in (unofficial; not part of crew).
##
##  Gets the project (a git repository at a commit, or an s3:// .tar.gz),
##  starts the project's worker command in its Docker image (on the host's
##  network, to reach the boss), and every 20 seconds copies the worker
##  command from S3 to the call file, so after a restart of the boss
##  elsewhere the workers find it again. When "done" appears in S3, copies
##  its logs to S3 and shuts down (launched to terminate on shutdown). A
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

## at the end: this machine's logs to S3 (one folder per machine), then shut down
finish() {
  cd /opt/project 2>/dev/null || true
  docker stop -t 30 worker || true
  token=$(curl -s -X PUT http://169.254.169.254/latest/api/token \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
  machine=$(curl -s -H "X-aws-ec2-metadata-token: $token" \
    http://169.254.169.254/latest/meta-data/instance-id)
  aws s3 sync cache/logs "$RUN_FOLDER/worker-logs/$machine" --only-show-errors || true
  aws s3 cp "$LOG" "$RUN_FOLDER/worker-logs/$machine/machine.log" --only-show-errors || true
  shutdown -h now
}
trap finish EXIT

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

## every 20 seconds: the boss's command, fresh from S3; stop when the run is done
while docker ps -q --filter name=worker | grep -q .; do
  aws s3 cp "$RUN_FOLDER/worker_call.R" "$CALL_FILE.new" --only-show-errors 2>/dev/null &&
    mv "$CALL_FILE.new" "$CALL_FILE"
  aws s3 ls "$RUN_FOLDER/done" > /dev/null 2>&1 && break
  sleep 20
done
docker logs worker | tail -50
