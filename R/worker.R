#' @title Run workers on this machine for a controller elsewhere
#' @export
#' @description Starts `workers` crew workers with the command in
#'   `call_file` (a copy of the file [crew_controller_remote()] writes) and
#'   keeps them going: a worker stops when its controller stops or cannot be
#'   reached, and is then started again with the command as it is in the file
#'   at that moment. So when the controller restarts, possibly on another
#'   machine, the workers find it again once the new file is copied here.
#'   Set up anything the workers need (environment variables, compiled
#'   models) before calling this: the workers inherit this R session's
#'   environment variables.
#' @param call_file The worker command file.
#' @param workers How many workers to run on this machine.
#' @param log_folder Where each worker's log goes: one file per worker,
#'   every start added to it, with the times it started and stopped.
#' @param seconds_interval How often to check the workers.
#' @param stop_file Stop (and stop the workers) once this file exists;
#'   `NULL` to run until the R session is stopped.
#' @return `NULL`, invisibly, once `stop_file` exists.
crew_remote_worker <- function(
  call_file,
  workers = parallelly::availableCores(),
  log_folder = file.path("cache", "logs", "workers"),
  seconds_interval = 10,
  stop_file = NULL
) {
  dir.create(log_folder, recursive = TRUE, showWarnings = FALSE)
  rscript <- file.path(R.home("bin"), "Rscript")
  running <- vector("list", workers)
  stamp <- function(what, log) {
    cat(sprintf("==== %s %s\n", what, format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
        file = log, append = TRUE)
  }
  message(sprintf("%d workers, reading the command from %s", workers, call_file))
  on.exit(for (process in running) if (!is.null(process)) process$kill())
  repeat {
    if (!is.null(stop_file) && file.exists(stop_file)) break
    for (i in seq_len(workers)) {
      if (!is.null(running[[i]]) && running[[i]]$is_alive()) next
      if (!file.exists(call_file)) next
      # each start writes to its own file, added to the worker's log when it stops
      log <- file.path(log_folder, sprintf("remote_worker_%d.log", i))
      this_start <- paste0(log, ".current")
      if (file.exists(this_start)) {
        file.append(log, this_start)
        unlink(this_start)
        stamp("stopped", log)
      }
      stamp("started", log)
      running[[i]] <- processx::process$new(
        rscript,
        c("--no-save", "--no-restore", "-e", readLines(call_file)),
        stdout = this_start,
        stderr = "2>&1"
      )
    }
    Sys.sleep(seconds_interval)
  }
  invisible()
}
