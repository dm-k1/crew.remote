## =====================================================================
##  A tiny pipeline to test crew.remote on AWS: 60 tasks that each wait 30
##  seconds and report which machine (and AWS region) ran them. Run on the
##  boss with CREW_REMOTE_ADDRESS set (aws-test/boss-data.sh).
## =====================================================================
library(targets)
tar_option_set(
  controller = crew.remote::crew_controller_remote(
    address = Sys.getenv("CREW_REMOTE_ADDRESS"),
    call_file = file.path("cache", "remote", "worker_call.R")
  ),
  storage = "main",
  retrieval = "main"
)

## where a task ran: the machine's host name, which on AWS names its region
## (e.g. ip-172-31-5-10.eu-west-1.compute.internal; the workers' containers
## share the host's network and so its name)
where <- function() {
  host <- Sys.info()[["nodename"]]
  region <- sub("^[^.]*[.]([a-z0-9-]+)[.]compute[.]internal$", "\\1", host)
  if (identical(region, host)) region <- "us-east-1 (ec2.internal) or unknown"
  data.frame(host = host, region = region)
}

list(
  tar_target(task_ids, seq_len(60)),
  tar_target(
    tasks,
    {
      Sys.sleep(30)
      cbind(task = task_ids, where(), pid = Sys.getpid(), finished = format(Sys.time()))
    },
    pattern = map(task_ids)
  )
)
