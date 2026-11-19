test_that("an empty address is refused", {
  skip_unless_local()
  folder <- withr_tempdir()
  expect_error(crew_controller_remote(address = "", call_file = file.path(folder, "call.R")))
})

test_that("the certificate is made once per address", {
  skip_unless_local()
  folder <- withr_tempdir()
  crew_tls_address("127.0.0.1", folder)
  first <- readLines(file.path(folder, "certificate.pem"))
  crew_tls_address("127.0.0.1", folder)
  expect_identical(readLines(file.path(folder, "certificate.pem")), first)
  crew_tls_address("localhost", folder)
  expect_false(identical(readLines(file.path(folder, "certificate.pem")), first))
  expect_identical(readLines(file.path(folder, "address")), "localhost")
})

test_that("workers started elsewhere take the tasks, and a lost worker's task crashes", {
  skip_unless_local()
  folder <- withr_tempdir()
  call_file <- file.path(folder, "call.R")
  controller <- crew_controller_remote(
    address = "127.0.0.1",
    call_file = call_file,
    port = free_port()
  )
  on.exit(controller$terminate(), add = TRUE)
  controller$start()
  for (i in 1:6) controller$push(command = {Sys.sleep(2); Sys.getpid()}, name = paste0("t", i))

  # the controller writes the command, with the address workers dial
  expect_true(wait_for(function() file.exists(call_file), controller))
  expect_match(readLines(call_file), "tls+tcp://127.0.0.1:", fixed = TRUE)

  # two workers in another process take every task
  stop_file <- file.path(folder, "stop")
  log_folder <- file.path(folder, "logs")
  machine <- start_remote_worker(call_file, workers = 2, stop_file, log_folder)
  on.exit(machine$kill_tree(), add = TRUE)
  controller$wait(mode = "all", seconds_timeout = 60)
  results <- controller$collect()
  expect_equal(nrow(results), 6)
  expect_true(all(results$status == "success"))
  expect_false(any(unlist(results$result) == Sys.getpid()))

  # killing a worker mid-task: crew reports a crash (targets re-runs it)
  controller$push(command = {Sys.sleep(20); "never"}, name = "lost")
  workers <- function() {
    Filter(function(p) any(grepl("crew_worker", ps::ps_cmdline(p))), ps::ps_children(machine$as_ps_handle()))
  }
  expect_true(wait_for(function() length(workers()) == 2, controller))
  Sys.sleep(3)
  lapply(workers(), ps::ps_kill)
  controller$wait(mode = "all", seconds_timeout = 60)
  lost <- controller$collect()
  expect_equal(lost$status, "crash")

  # the workers' logs record each start; the machine stops on its stop file
  writeLines("stop", stop_file)
  expect_true(wait_for(function() !machine$is_alive()))
  expect_true(any(grepl("==== started", readLines(file.path(log_folder, "remote_worker_1.log")))))
})
