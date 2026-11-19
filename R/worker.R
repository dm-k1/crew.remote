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
#'
#'   While the controller cannot be reached (workers stop within
#'   `seconds_short` of starting), each further start waits twice as long as
#'   the one before, up to `seconds_backoff_max`; a new command in
#'   `call_file` (a controller elsewhere) is tried at once.
#' @param call_file The worker command file.
#' @param workers How many workers to run on this machine.
#' @param log_folder Where each worker's log goes: one file per worker,
#'   every start added to it, with the times it started and stopped.
#' @param seconds_interval How often to check the workers.
#' @param seconds_short A start that ends sooner than this counts as not
#'   having reached the controller.
#' @param seconds_backoff_max The longest wait between such starts.
#' @param stop_file Stop (and stop the workers) once this file exists;
#'   `NULL` to run until the R session is stopped.
#' @return `NULL`, invisibly, once `stop_file` exists.
crew_remote_worker <- function(
  call_file,
  workers = parallelly::availableCores(),
  log_folder = file.path("cache", "logs", "workers"),
  seconds_interval = 10,
  seconds_short = 60,
  seconds_backoff_max = 300,
  stop_file = NULL
) {
  dir.create(log_folder, recursive = TRUE, showWarnings = FALSE)
  rscript <- file.path(R.home("bin"), "Rscript")
  running <- vector("list", workers)
  # per worker: when and with which command it last started, how many short
  # starts in a row it has had, and the earliest time of its next start
  started <- rep(-Inf, workers)
  started_with <- vector("list", workers)
  short_starts <- integer(workers)
  not_before <- rep(-Inf, workers)
  now <- function() as.numeric(Sys.time())
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
      call <- readLines(call_file)
      if (!is.null(running[[i]])) {
        # it stopped: back off if it did not reach the controller, unless the
        # command is new
        if (identical(call, started_with[[i]]) && now() - started[i] < seconds_short) {
          short_starts[i] <- short_starts[i] + 1L
          wait <- min(seconds_backoff_max, seconds_interval * 2^(short_starts[i] - 1L))
          not_before[i] <- started[i] + wait
        } else {
          short_starts[i] <- 0L
          not_before[i] <- -Inf
        }
        running[i] <- list(NULL)
      }
      if (now() < not_before[i] && identical(call, started_with[[i]])) next
      # each start writes to its own file, added to the worker's log when it stops
      log <- file.path(log_folder, sprintf("remote_worker_%d.log", i))
      this_start <- paste0(log, ".current")
      if (file.exists(this_start)) {
        file.append(log, this_start)
        unlink(this_start)
        stamp("stopped", log)
      }
      stamp("started", log)
      started[i] <- now()
      started_with[[i]] <- call
      running[[i]] <- processx::process$new(
        rscript,
        c("--no-save", "--no-restore", "-e", call),
        stdout = this_start,
        stderr = "2>&1"
      )
    }
    Sys.sleep(seconds_interval)
  }
  invisible()
}
