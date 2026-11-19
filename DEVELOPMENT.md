# Developing crew.remote

Notes for picking this up again: where it stands, how to test a change, and
what is known to be weak.

## Where it stands (19 November 2026)

- Version 0.2.0. Built for [flatcor-validation](https://github.com/dm-k1/flatcor-validation),
  whose local branch `multi-machine` uses it (not merged, not on GitHub; see
  that branch's `cluster/README.md`, "On several machines"). The validation's
  real runs of November 2026 ran on single machines, so crew.remote has not
  yet carried a real run.
- Tested at all three levels (see README, "Testing"): the R tests and the
  end-to-end test without AWS pass in GitHub Actions; on AWS it survived a
  real spot interruption (Fault Injection Service), a terminated and replaced
  boss, workers in two regions, and a machine whose setup failed.
- Nothing is left on AWS: `inst/aws/teardown.sh` removed the roles and
  security groups; `inst/aws/setup.sh` makes them again.

## How to test a change

Cheapest first; real AWS only once the first two pass.

1. **R tests:** `devtools::test()` (they start R processes and listen on local
   ports; `NOT_CRAN=true` for `R CMD check`). GitHub Actions runs `R CMD check`
   on Linux and macOS for every push to main (`.github/workflows/R-CMD-check.yaml`).
2. **End to end without AWS:** GitHub Actions runs `tests/end-to-end/local`
   (Docker Compose: moto for S3, AWS's metadata mock for spot notices) for
   every push (`end-to-end.yaml`). With Docker locally:
   `docker compose -f tests/end-to-end/local/compose.yaml up --build --abort-on-container-exit --exit-code-from boss`.
   It cannot see AWS permissions (moto does not enforce them), real spot
   capacity, or networking between regions.
3. **End to end on AWS** (about 10 minutes and a few cents on t3 machines).
   GitHub Actions must first have built the commit's test image
   (`test-image.yaml` publishes `ghcr.io/dm-k1/crew.remote-test:sha-<commit>`,
   public). Then, with the AWS command line tool logged in:

   ```bash
   export CREW_REMOTE_BUCKET=<bucket> CREW_REMOTE_BUCKET_REGION=<its region>
   inst/aws/setup.sh                                    # once: the roles
   tests/end-to-end/aws/run.sh my-test <commit> eu-west-1 "eu-west-1 eu-central-1"
   # optional, once the workers have taken tasks:
   tests/end-to-end/aws/interrupt.sh eu-central-1 my-test   # a real spot interruption
   # optional, a lost boss: terminate the instance named crew-remote-boss-my-test, then
   tests/end-to-end/aws/run.sh my-test <commit> eu-west-1 "eu-west-1 eu-central-1" --boss-only
   # when s3://<bucket>/my-test/tasks.csv is there, wait two minutes, then
   RUN_FOLDER=s3://<bucket>/my-test TASKS=60 EXPECT_SPOT=1 Rscript tests/end-to-end/check.R
   inst/aws/teardown.sh "eu-west-1 eu-central-1"        # what the run left; results stay in S3
   ```

   `interrupt.sh` has not run as a script yet (the same experiment was run by
   hand on 19 November 2026).

## Known weak spots and ideas

- **No worker authentication** (mirai has none): safety rests on the boss's
  security group, opened only to the run's own worker machines. A stricter
  setup would put all machines in private networks joined by VPC peering.
- **The TLS key**: crew wants PKCS#8, nanonext writes PKCS#1, so
  `crew_tls_address()` calls the `openssl` command line tool. A cleaner fix
  belongs in crew (let `crew_tls()` make a certificate for a given address,
  or accept both key forms): worth an issue there.
- **"Launches" that start nothing**: the launcher only publishes the worker
  command, which crew counts as launches that never connect. Harmless so far.
- **The boss rewrites the worker command often** (crew's random stream in it
  changes), so S3 gets a new copy every 20 seconds; harmless but noisy.
- **Capacity rebalancing** is off by default: with a spot quota of exactly one
  machine per region, a replacement cannot start before the old machine goes.
- Upstream: crew's author started a launcher for workers started elsewhere and
  preferred a plugin ([crew#200](https://github.com/wlandau/crew/issues/200));
  crew.remote could be offered as an example there.
