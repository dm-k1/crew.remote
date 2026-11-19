# crew.remote

> **Unofficial. Not part of crew.** crew.remote is a personal package. It is
> not part of [crew](https://wlandau.github.io/crew/), and it is not made,
> reviewed or endorsed by the authors of crew or
> [mirai](https://mirai.r-lib.org/). The name only says what it plugs into.
> Please report problems [here](https://github.com/dm-k1/crew.remote/issues),
> not to crew. Early version: tested on one project so far.

crew.remote lets a [crew](https://wlandau.github.io/crew/) controller (and so a
[targets](https://docs.ropensci.org/targets/) pipeline) use **workers on other
machines**: other computers, or cloud machines in one or several regions. One
machine, the boss, runs the pipeline; the workers dial in, take tasks and send
back results. A worker that disappears (a cloud machine taken back) loses only
its current task, which targets runs again.

It is a launcher plugin, written with crew's documented plugin interface
(`vignette("plugins", package = "crew")`). crew has local and cluster
launchers but no launcher for workers started elsewhere: its author began one
and preferred a plugin ([crew#200](https://github.com/wlandau/crew/issues/200)).

## How it works

- `crew_controller_remote(address = ...)` listens on a port (5555) on all of
  the boss's addresses. Instead of starting workers, it writes the command a
  worker must run to a file (`cache/remote/worker_call.R`). The command holds
  the address workers dial and the boss's TLS certificate, so traffic is
  encrypted and a worker only talks to the real boss.
- Copy that file to each worker machine (by hand, a shared folder, S3) and run
  `crew_remote_worker("cache/remote/worker_call.R", workers = ...)` there. It
  starts the workers and keeps them going: a worker stops when the boss's
  controller stops or cannot be reached, and starts again with the command in
  the file at that moment.

## Security

What protects a run, and what does not:

- **Who can connect.** mirai has no password or client certificate for
  workers: whoever can reach the port can take tasks (and see their inputs)
  or send back wrong results. So the network must let in only your own
  machines: a firewall, a VPN, or a cloud security group. The AWS scripts
  open the port only to the public addresses of the run's own worker
  machines, updated every 20 seconds, and closed otherwise. Do not open the
  port to the whole internet.
- **The traffic.** TLS encrypts it, and a worker checks the controller's
  certificate, so it cannot be sent to a fake controller. The private key
  stays on the boss (readable by its owner only); the worker command file
  holds only the certificate, which is public by nature.
- **On AWS** the scripts follow AWS's usual advice: instance roles instead of
  keys (no access keys on any machine), least privilege (the boss may change
  only its own security groups and delete only the run's fleets; workers may
  read the bucket and write only their own logs: `worker-policy.json`),
  IMDSv2 required, encrypted disks, no SSH (use Systems Manager if you must
  get in), and worker machines in a security group with no inbound rules at
  all. Keep the bucket's public access blocked.
- **Not covered.** Anyone who controls a machine you let in can tamper with
  results; a worker's address that AWS gives to another account within the 20
  seconds before it is closed could connect (TLS still protects the
  controller's identity, not yours). A stricter setup puts all machines in
  private networks joined by VPC peering, with the port open to private
  addresses only; the scripts do not set that up.

## In a targets pipeline

```r
# _targets.R, on the boss
library(targets)
tar_option_set(
  controller = crew.remote::crew_controller_remote(address = "203.0.113.7"),
  storage = "main",    # the workers share no disk with the boss: the boss
  retrieval = "main"   # stores every result and sends each task its inputs
)
```

Targets that read or write files on the boss need `deployment = "main"`.
The worker machines need the same R packages (best: the same Docker image)
and, if tasks use project files, the same project folder. Where a target runs
is not among targets' reasons to rerun it (`?tar_cue`), so switching between
this and a local controller keeps finished targets.

## On AWS

`system.file("aws", package = "crew.remote")` holds scripts for Amazon Web
Services (Amazon Linux 2023 and Docker on every machine):

- `launch_boss.sh`: the boss, one on-demand instance (AWS does not take it
  back) with a security group that starts closed. It runs your own user data
  script, into which it puts `helpers.sh`: functions to copy the worker
  command to S3, to open the port to exactly the run's worker machines, and at
  the end to stop them and delete their fleets.
- `launch_workers.sh`: one EC2 Fleet of spot instances per region (each region
  has its own spot quota). Type "maintain": AWS replaces a machine it takes
  back, without anyone watching. The fleet ends after a given number of hours,
  machines and all. Its machines run `worker-data.sh`, which reads the worker
  command from S3 every 20 seconds and stops when the boss writes `done`.
  When AWS gives notice that it takes a machine back (two minutes ahead), the
  machine copies its logs to S3 and stops; its running tasks go to other
  workers. A machine whose workers stop by themselves (a failed setup, say
  too little memory) copies its logs and stays up, idle, until the safety
  cutoff, rather than being replaced by one that fails the same way. Why each
  machine stopped is in `s3://<bucket>/<run name>/worker-stops/`. `CREW_REMOTE_CAPACITY_REBALANCE=1` starts a replacement as soon as
  AWS signals a machine is at risk (needs spot quota for one machine more).
- `boss-policy.json` and `worker-policy.json`: what the boss's and the
  workers' roles may do (replace `__BUCKET__`).

**Testing a lost machine for real.** AWS Fault Injection Service can send a
real spot interruption (action `aws:ec2:send-spot-instance-interruptions`) to
the run's worker machines (tag `crew-remote-run`), which is the honest test of
what happens when AWS takes one back.

Settings are environment variables (`CREW_REMOTE_BUCKET`, `CREW_REMOTE_IMAGE`,
...; see the top of each script). An example project that uses all of this:
[flatcor-validation](https://github.com/dm-k1/flatcor-validation)
(`cluster/aws/`, `cluster/README.md`).

## Testing

Three levels, cheapest first. Changes are tested at the first two; real AWS
only as a final check.

1. **R tests** (`tests/testthat/`): a controller and workers in separate R
   processes on one machine; a killed worker's task is reported as a crash;
   workers that cannot reach the controller back off. GitHub Actions runs
   them (R CMD check) on Linux and macOS.
2. **End to end without AWS** (`tests/end-to-end/local/`, Docker Compose;
   GitHub Actions runs it): a boss and two worker containers, S3 replaced by
   [moto](https://github.com/getmoto/moto), and the instance metadata service
   by AWS's [amazon-ec2-metadata-mock](https://github.com/aws/amazon-ec2-metadata-mock),
   which gives one worker a spot interruption notice. Partway through, the
   boss is lost and comes back under another address.
3. **End to end on AWS** (`tests/end-to-end/aws/run.sh`, a few cents on small
   burstable machines): a boss and spot fleets in two regions. A real spot
   interruption can be sent with AWS Fault Injection Service, and the boss
   can be terminated and replaced (`run.sh ... --boss-only`).

Both end-to-end tests run the same tiny pipeline
(`tests/end-to-end/pipeline/_targets.R`) and the same checks
(`tests/end-to-end/check.R`): every task done once, tasks on at least two
machines, finished tasks stay finished when the boss is lost, the workers find
the new boss, an interrupted machine stops and copies its logs, and a machine
whose setup fails reports it (locally, one worker's setup fails on purpose).

## Install

```r
remotes::install_github("dm-k1/crew.remote")
```

Needs the `openssl` command line tool on the boss (to write the TLS key in the
form crew wants).
