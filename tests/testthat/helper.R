## Tests start local R processes and listen on local ports: not on CRAN
skip_unless_local <- function() {
  skip_on_cran()
  skip_if(!nzchar(Sys.which("openssl")), "needs the openssl command line tool")
}

## A free port
free_port <- function() parallelly::freePort()

## Wait until condition() is TRUE, scaling the controller meanwhile
wait_for <- function(condition, controller = NULL, seconds = 30) {
  start <- Sys.time()
  while (!condition()) {
    if (!is.null(controller)) controller$scale()
    if (difftime(Sys.time(), start, units = "secs") > seconds) return(FALSE)
    Sys.sleep(0.25)
  }
  TRUE
}

## Run crew_remote_worker() in its own R process
start_remote_worker <- function(call_file, workers, stop_file, log_folder) {
  processx::process$new(
    file.path(R.home("bin"), "Rscript"),
    c("-e", sprintf(
      "crew.remote::crew_remote_worker('%s', workers = %d, log_folder = '%s', seconds_interval = 1, stop_file = '%s')",
      call_file, workers, log_folder, stop_file
    )),
    env = c("current", R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
  )
}

## A temporary folder for one test, removed afterwards
withr_tempdir <- function(env = parent.frame()) {
  folder <- tempfile("crew_remote_")
  dir.create(folder)
  do.call(on.exit, list(substitute(unlink(f, recursive = TRUE), list(f = folder)), add = TRUE), envir = env)
  folder
}
