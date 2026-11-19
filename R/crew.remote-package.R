#' crew.remote: workers on other machines for crew (unofficial)
#'
#' **Not an official crew package.** crew.remote is not part of
#' [crew](https://wlandau.github.io/crew/) and is not made, reviewed or
#' endorsed by the authors of crew or mirai. It uses only crew's documented
#' launcher plugin interface (`vignette("plugins", package = "crew")`).
#'
#' The controller ([crew_controller_remote()]) starts no workers. It writes
#' the command a worker must run to a file; copy that file to other machines
#' (by hand, a shared folder, or S3) and run [crew_remote_worker()] there.
#' The workers dial in over TLS, take tasks and send back results. A task
#' whose worker disappears is reported as a crash, which targets re-runs.
#'
#' Security: mirai has no password for workers. Whoever can reach the port
#' can take tasks, so let only your own machines through (a firewall or
#' cloud security group). TLS encrypts the traffic and lets workers check
#' they reached the real controller.
#'
#' @keywords internal
#' @importFrom R6 R6Class
"_PACKAGE"
