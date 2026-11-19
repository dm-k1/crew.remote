#' @title TLS configuration for workers that dial `address`
#' @export
#' @description A worker checks the controller's certificate against the
#'   address it dials, so the certificate must be made for that address.
#'   mirai's automatic certificate is made for the address the controller
#'   listens on, which a machine behind NAT (such as a cloud instance with a
#'   public IP) cannot listen on. This makes a certificate for `address`
#'   once and keeps it in `folder`, so the worker command stays the same
#'   across controllers; a new address gets a new certificate.
#' @details nanonext makes the key and certificate, as for mirai's own
#'   automatic TLS. crew wants the key in PKCS#8 form, into which the openssl
#'   command line tool rewrites it (it must be on the PATH).
#' @param address The address workers dial.
#' @param folder Where the key and certificate are kept (the key is
#'   readable by its owner only).
#' @return A `crew::crew_tls()` object in mode `"custom"`.
crew_tls_address <- function(address, folder) {
  dir.create(folder, recursive = TRUE, showWarnings = FALSE)
  key <- file.path(folder, "key.pem")
  certificate <- file.path(folder, "certificate.pem")
  made_for <- file.path(folder, "address")
  if (!file.exists(made_for) || !identical(readLines(made_for), address)) {
    made <- nanonext::write_cert(cn = address)
    rsa_key <- file.path(folder, "rsa_key.pem")
    writeLines(trimws(made$server[2]), rsa_key)
    status <- system2("openssl", c("pkey", "-in", rsa_key, "-out", key))
    unlink(rsa_key)
    if (status != 0) stop("openssl could not rewrite the TLS key")
    Sys.chmod(key, "600")
    writeLines(trimws(made$server[1]), certificate)
    writeLines(address, made_for)
  }
  crew::crew_tls(mode = "custom", key = key, certificates = certificate)
}
