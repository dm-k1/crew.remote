#' @title Launcher class for workers started elsewhere
#' @export
#' @description An `R6` launcher that starts no workers. Whenever crew asks
#'   for workers, it writes the command they must run to `call_file`, with
#'   the address the controller listens on replaced by `address`, the one
#'   workers dial. Use it through [crew_controller_remote()].
crew_class_launcher_remote <- R6::R6Class(
  classname = "crew_class_launcher_remote",
  inherit = crew::crew_class_launcher,
  public = list(
    #' @field address The address workers dial (host name or IP address).
    address = NULL,
    #' @field call_file The file the worker command is written to.
    call_file = NULL,

    #' @description Create the launcher.
    #' @param ... Arguments of `crew::crew_class_launcher$new()`.
    #' @param address The address workers dial.
    #' @param call_file The file the worker command is written to.
    initialize = function(..., address = NULL, call_file = NULL) {
      super$initialize(...)
      self$address <- address
      self$call_file <- call_file
    },

    #' @description Check the launcher, crew's checks first.
    validate = function() {
      super$validate()
      crew::crew_assert(
        self$address,
        is.character(.), length(.) == 1L, nzchar(.), !anyNA(.),
        message = "address must be one nonempty character string"
      )
      crew::crew_assert(
        self$call_file,
        is.character(.), length(.) == 1L, nzchar(.), !anyNA(.),
        message = "call_file must be one nonempty character string"
      )
      invisible()
    },

    #' @description "Launch" workers: write the command they must run.
    #'   Written to a temporary file first and then moved in place, so a
    #'   reader never sees half a command.
    #' @param call The worker command, from crew.
    #' @param n How many workers crew asks for (not used: the machines
    #'   elsewhere decide how many workers they run).
    launch_workers = function(call, n) {
      listening <- self$settings()$url
      dialled <- sub("//[^/:]+:", paste0("//", self$address, ":"), listening)
      call <- sub(listening, dialled, call, fixed = TRUE)
      dir.create(dirname(self$call_file), recursive = TRUE, showWarnings = FALSE)
      temporary <- paste0(self$call_file, ".new")
      writeLines(call, temporary)
      file.rename(temporary, self$call_file)
      invisible()
    }
  )
)

#' @title Controller for workers started elsewhere
#' @export
#' @description A crew controller whose workers run on other machines. It
#'   listens on `port` on all of this machine's addresses and writes the
#'   command workers must run to `call_file`; run [crew_remote_worker()]
#'   with a copy of that file on each machine. It takes the arguments of
#'   [crew::crew_controller_local()] (as crew's plugin vignette advises),
#'   with defaults suited to workers elsewhere, and `address` and `call_file`.
#' @inheritParams crew::crew_controller_local
#' @param address The address workers dial: a host name or IP address of
#'   this machine as the workers see it (on a cloud machine, its public IP).
#' @param call_file The file the worker command is written to.
#' @param workers The most tasks handed out at once. More than there will be
#'   workers is fine: the rest wait in the queue until a worker is free.
#' @param host The address the controller listens on (default: all of this
#'   machine's).
#' @param port The port it listens on, fixed so a firewall can let it through.
#' @param tls TLS configuration (default: a certificate for `address`, kept
#'   next to `call_file`; see [crew_tls_address()]).
#' @param seconds_idle A worker with nothing to do this long stops;
#'   [crew_remote_worker()] then starts a new one.
#' @return A crew controller.
#' @examples
#' \dontrun{
#' controller <- crew_controller_remote(address = "203.0.113.7")
#' # in a targets pipeline: tar_option_set(controller = controller,
#' #   storage = "main", retrieval = "main")
#' }
crew_controller_remote <- function(
  address,
  call_file = file.path("cache", "remote", "worker_call.R"),
  name = NULL,
  workers = 256L,
  host = "0.0.0.0",
  port = 5555L,
  tls = crew_tls_address(address, dirname(call_file)),
  serialization = NULL,
  profile = crew::crew_random_name(),
  seconds_interval = 0.25,
  seconds_timeout = 60,
  seconds_launch = 30,
  seconds_idle = 3600,
  seconds_wall = Inf,
  tasks_max = Inf,
  tasks_timers = 0L,
  reset_globals = TRUE,
  reset_packages = FALSE,
  reset_options = FALSE,
  garbage_collection = FALSE,
  r_arguments = c("--no-save", "--no-restore"),
  options_metrics = crew::crew_options_metrics(),
  crashes_max = 5L,
  backup = NULL
) {
  client <- crew::crew_client(
    host = host,
    port = port,
    tls = tls,
    serialization = serialization,
    profile = profile,
    seconds_interval = seconds_interval,
    seconds_timeout = seconds_timeout
  )
  launcher <- crew_class_launcher_remote$new(
    name = name,
    workers = workers,
    seconds_interval = seconds_interval,
    seconds_timeout = seconds_timeout,
    seconds_launch = seconds_launch,
    seconds_idle = seconds_idle,
    seconds_wall = seconds_wall,
    tasks_max = tasks_max,
    tasks_timers = tasks_timers,
    tls = tls,
    r_arguments = r_arguments,
    options_metrics = options_metrics,
    address = address,
    call_file = call_file
  )
  controller <- crew::crew_controller(
    client = client,
    launcher = launcher,
    reset_globals = reset_globals,
    reset_packages = reset_packages,
    reset_options = reset_options,
    garbage_collection = garbage_collection,
    crashes_max = crashes_max,
    backup = backup
  )
  controller$validate()
  controller
}
