## A worker machine of the AWS end-to-end test (run from the repository's top
## folder, in the test image, which has every package): crew.remote's workers,
## two per machine, reading the boss's command from the file
## inst/aws/worker-data.sh keeps fresh
crew.remote::crew_remote_worker("cache/remote/worker_call.R", workers = 2)
