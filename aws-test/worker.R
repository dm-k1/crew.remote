## A worker machine of the AWS test: the packages, then crew.remote's workers
## (two per machine), reading the boss's command from the file worker-data.sh
## keeps fresh
source("aws-test/setup.R")
crew.remote::crew_remote_worker("cache/remote/worker_call.R", workers = 2)
