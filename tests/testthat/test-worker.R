## crew_remote_worker(): back-off while the controller cannot be reached

test_that("workers that cannot reach the controller back off", {
  skip_unless_local()
  folder <- withr_tempdir()
  # a command for a controller that is not there (nothing listens on the port)
  call_file <- file.path(folder, "call.R")
  writeLines(sprintf(
    "crew::crew_worker(settings = list(url = 'tcp://127.0.0.1:%d', dispatcher = TRUE, asyncdial = FALSE), controller = 'none')",
    free_port()
  ), call_file)
  stop_file <- file.path(folder, "stop")
  log_folder <- file.path(folder, "logs")
  machine <- start_remote_worker(call_file, workers = 1, stop_file, log_folder)
  on.exit(machine$kill_tree(), add = TRUE)
  Sys.sleep(20)
  writeLines("stop", stop_file)
  expect_true(wait_for(function() !machine$is_alive()))
  starts <- sum(grepl("==== started", readLines(file.path(log_folder, "remote_worker_1.log"))))
  # every second without back-off (about 20); with it at 0, 1, 3, 7, 15 s
  expect_gte(starts, 2)
  expect_lte(starts, 7)
})
