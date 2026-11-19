## =====================================================================
##  The checks of crew.remote's end-to-end tests, the same locally and on
##  AWS. They read what the run left in S3 (RUN_FOLDER): tasks.csv (written by
##  the boss), restarted_at.txt (if the boss was lost and restarted), the
##  workers' logs and why each machine stopped. Exits 1 if a check fails.
##
##    RUN_FOLDER=s3://... TASKS=60 [EXPECT_SPOT=1] [EXPECT_FAILED=<machine>] Rscript tests/end-to-end/check.R
## =====================================================================
folder <- Sys.getenv("RUN_FOLDER")
expected <- as.integer(Sys.getenv("TASKS", "60"))
s3_lines <- function(path) {
  suppressWarnings(system2("aws", c("s3", "cp", paste0(folder, "/", path), "-"),
                           stdout = TRUE, stderr = FALSE))
}

tasks <- read.csv(text = s3_lines("tasks.csv"))
print(table(tasks$host))
checks <- c(
  "every task done, each once" = nrow(tasks) == expected && setequal(tasks$task, seq_len(expected)),
  "tasks ran on at least two machines" = length(unique(tasks$host)) >= 2
)

# the boss lost and restarted: what was finished stays finished, and the
# workers find the new boss
restarted <- s3_lines("restarted_at.txt")
if (length(restarted) > 0) {
  restarted <- as.POSIXct(restarted, format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
  finished <- as.POSIXct(tasks$finished, tz = "UTC")
  checks["tasks finished before the boss was lost stayed finished"] <- any(finished < restarted)
  checks["the workers found the new boss"] <- length(unique(tasks$host[finished >= restarted])) >= 2
}

# why each worker machine stopped (worker-stops/<machine>.txt)
stops_folder <- tempfile()
system2("aws", c("s3", "cp", "--recursive", paste0(folder, "/worker-stops"), stops_folder, "--only-show-errors"))
stop_files <- list.files(stops_folder, full.names = TRUE)
stops <- setNames(vapply(stop_files, function(f) paste(readLines(f, warn = FALSE), collapse = " "), ""),
                  sub("[.]txt$", "", basename(stop_files)))
print(stops)

# a spot interruption notice: the machine stopped and copied its logs
if (identical(Sys.getenv("EXPECT_SPOT"), "1")) {
  logs <- tempfile()
  system2("aws", c("s3", "cp", "--recursive", paste0(folder, "/worker-logs"), logs, "--only-show-errors"))
  checks["a machine got the spot notice, stopped and copied its logs"] <-
    any(stops == "AWS takes this machine back") && length(list.files(logs, recursive = TRUE)) > 0
}

# a machine whose setup failed (EXPECT_FAILED: its name) says so; every
# other machine stopped because the run was done or AWS took it back
failed <- Sys.getenv("EXPECT_FAILED")
if (nzchar(failed)) {
  checks["the machine whose setup failed reported it"] <- identical(unname(stops[failed]), "the workers stopped")
}
others <- stops[setdiff(names(stops), failed)]
checks["the other machines stopped for the expected reasons"] <-
  all(others %in% c("the run is done", "AWS takes this machine back"))

for (name in names(checks)) cat(if (isTRUE(checks[[name]])) "PASS" else "FAIL", name, "\n")
quit(status = if (all(checks)) 0 else 1)
