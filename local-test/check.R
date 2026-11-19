## The checks of the local test (run by the boss at the end): every task done,
## both workers took tasks, worker-b got the spot notice, stopped and copied
## its logs, and the tasks after that went to worker-a. Exits 1 if not.
folder <- Sys.getenv("RUN_FOLDER")
tasks <- read.csv(file.path("aws-test", "tasks.csv"))
read_s3 <- function(path) {
  out <- suppressWarnings(system2("aws", c("s3", "cp", paste0(folder, "/", path), "-"),
                                  stdout = TRUE, stderr = FALSE))
  if (length(out) == 0) NA_character_ else paste(out, collapse = "\n")
}
stopped_b <- read_s3("worker-logs/worker-b/workers/stopped.txt")
expected <- as.integer(Sys.getenv("TASKS"))
print(table(tasks$host))
checks <- c(
  "every task done" = nrow(tasks) == expected && setequal(tasks$task, seq_len(expected)),
  "worker-a took tasks" = any(tasks$host == "worker-a"),
  "worker-b took tasks" = any(tasks$host == "worker-b"),
  "worker-b got the spot notice and copied its logs" =
    isTRUE(grepl("AWS takes this machine back", stopped_b)),
  "the last tasks went to worker-a" = tail(tasks$host[order(tasks$finished)], 1) == "worker-a"
)
for (name in names(checks)) cat(if (checks[[name]]) "PASS" else "FAIL", name, "\n")
quit(status = if (all(checks)) 0 else 1)
