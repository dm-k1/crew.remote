# crew.remote 0.2.0

- Tests: R tests per part (`tests/testthat/`), and end-to-end tests in
  `tests/end-to-end/`: the same pipeline and checks without AWS (Docker
  Compose with moto and AWS's metadata mock, in GitHub Actions) and on AWS,
  including a lost and restarted boss.

- Workers that cannot reach the controller back off: each further start
  waits twice as long, up to 5 minutes; a new worker command is tried at once.
- AWS: encrypted disks; worker machines in a security group with no inbound
  rules; a worker machine that gets AWS's spot interruption notice copies its
  logs and stops; optional capacity rebalancing (`CREW_REMOTE_CAPACITY_REBALANCE=1`);
  `worker-policy.json`, a least-privilege role for the workers.
- README: a security section (what is protected and what is not).
- GitHub Actions: R CMD check with the tests on Linux and macOS.

# crew.remote 0.1.0

- First version: `crew_controller_remote()`, `crew_tls_address()`,
  `crew_remote_worker()`, and AWS scripts for a boss and spot worker fleets.
