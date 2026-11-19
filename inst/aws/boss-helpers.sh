## =====================================================================
##  crew.remote: shell functions for the boss machine on AWS (unofficial;
##  not part of crew). launch_boss.sh puts them into the boss's user data
##  where it has the line "# crew.remote: boss helpers".
##
##    crew_remote_publish_call <call file> <s3 run folder>
##        the worker command to S3 whenever it changes
##    crew_remote_let_workers_in <port> <run name> "<worker regions>"
##        the boss's security group lets in, on the port, exactly the
##        public addresses of the run's worker machines (tag crew-remote-run)
##    crew_remote_stop_workers <s3 run folder> <run name> "<worker regions>"
##        writes "done" (workers then stop and copy their logs), waits 90
##        seconds, and deletes the run's worker fleets, machines and all
## =====================================================================

## this instance's own details (the instance metadata service, IMDSv2)
crew_remote_metadata() {
  local token
  token=$(curl -s -X PUT http://169.254.169.254/latest/api/token \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
  curl -s -H "X-aws-ec2-metadata-token: $token" "http://169.254.169.254/latest/meta-data/$1"
}

crew_remote_publish_call() {
  local call="$1" folder="$2"
  if [ -f "$call" ] && ! cmp -s "$call" /tmp/crew_remote_published_call; then
    aws s3 cp "$call" "$folder/worker_call.R" --only-show-errors &&
      cp "$call" /tmp/crew_remote_published_call
  fi
}

crew_remote_let_workers_in() {
  local port="$1" run="$2" regions="$3" region mac group wanted="" allowed address cidr
  region=$(crew_remote_metadata placement/region)
  mac=$(crew_remote_metadata mac)
  group=$(crew_remote_metadata "network/interfaces/macs/$mac/security-group-ids" | head -1)
  for worker_region in $regions; do
    wanted="$wanted $(aws ec2 describe-instances --region "$worker_region" \
      --filters "Name=tag:crew-remote-run,Values=$run" "Name=instance-state-name,Values=pending,running" \
      --query 'Reservations[].Instances[].PublicIpAddress' --output text)"
  done
  allowed=$(aws ec2 describe-security-group-rules --region "$region" \
    --filters "Name=group-id,Values=$group" \
    --query "SecurityGroupRules[?!IsEgress && FromPort==\`$port\`].CidrIpv4" --output text)
  for address in $wanted; do
    [ "$address" = "None" ] && continue
    echo " $allowed " | grep -q " $address/32 " ||
      aws ec2 authorize-security-group-ingress --region "$region" --group-id "$group" \
        --protocol tcp --port "$port" --cidr "$address/32" > /dev/null
  done
  for cidr in $allowed; do
    echo " $wanted " | grep -q " ${cidr%/32} " ||
      aws ec2 revoke-security-group-ingress --region "$region" --group-id "$group" \
        --protocol tcp --port "$port" --cidr "$cidr" > /dev/null
  done
}

crew_remote_stop_workers() {
  local folder="$1" run="$2" regions="$3" fleets
  echo done | aws s3 cp - "$folder/done" --only-show-errors || true
  sleep 90
  for worker_region in $regions; do
    fleets=$(aws ec2 describe-fleets --region "$worker_region" \
      --query "Fleets[?FleetState=='active' && Tags[?Key=='crew-remote-run' && Value=='$run']].FleetId" \
      --output text)
    # shellcheck disable=SC2086  # a list of fleet ids
    [ -n "$fleets" ] && aws ec2 delete-fleets --region "$worker_region" \
      --fleet-ids $fleets --terminate-instances || true
  done
}
