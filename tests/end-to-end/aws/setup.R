## The packages for the AWS end-to-end test, in the plain rocker/r-ver image:
## the system library GLPK (igraph, which targets needs, links to it),
## targets and crew.remote's dependencies as binaries from Posit's package
## manager (fast), then crew.remote itself from this checkout. Run from the
## repository's top folder.
system("apt-get update -qq && apt-get install -y -qq --no-install-recommends libglpk40 > /dev/null")
options(repos = c(CRAN = "https://p3m.dev/cran/__linux__/noble/latest"))
install.packages(c("targets", "crew", "nanonext", "parallelly", "processx", "R6"))
install.packages(".", repos = NULL, type = "source")
