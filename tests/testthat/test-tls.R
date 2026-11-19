## crew_tls_address(): one certificate per address

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
