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

**Security.** mirai has no password for workers: whoever can reach the port
can take tasks. Let only your own machines through (a firewall, a VPN, a
cloud security group; the AWS scripts below do this per run).

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
  script, into which it puts `boss-helpers.sh`: functions to copy the worker
  command to S3, to open the port to exactly the run's worker machines, and at
  the end to stop them and delete their fleets.
- `launch_workers.sh`: one EC2 Fleet of spot instances per region (each region
  has its own spot quota). Type "maintain": AWS replaces a machine it takes
  back, without anyone watching. The fleet ends after a given number of hours,
  machines and all. Its machines run `worker-data.sh`, which reads the worker
  command from S3 every 20 seconds and stops when the boss writes `done`.
- `boss-policy.json`: what the boss's role may do (replace `__BUCKET__`).

Settings are environment variables (`CREW_REMOTE_BUCKET`, `CREW_REMOTE_IMAGE`,
...; see the top of each script). An example project that uses all of this:
[flatcor-validation](https://github.com/dm-k1/flatcor-validation)
(`cluster/aws/`, `cluster/README.md`).

## Install

```r
remotes::install_github("dm-k1/crew.remote")
```

Needs the `openssl` command line tool on the boss (to write the TLS key in the
form crew wants).
