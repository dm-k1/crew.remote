## =====================================================================
##  A tiny pipeline to test crew.remote: TASKS tasks (default 60) that each
##  wait TASK_SECONDS (default 30) and report which machine (and AWS region)
##  ran them. Run on the boss with CREW_REMOTE_ADDRESS set (on AWS by
##  aws-test/boss-data.sh, locally by local-test/boss.sh).
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
  tar_target(task_ids, seq_len(as.integer(Sys.getenv("TASKS", "60")))),
  tar_target(
    tasks,
    {
      Sys.sleep(as.numeric(Sys.getenv("TASK_SECONDS", "30")))
      cbind(task = task_ids, where(), pid = Sys.getpid(), finished = format(Sys.time()))
    },
    pattern = map(task_ids)
  )
)
