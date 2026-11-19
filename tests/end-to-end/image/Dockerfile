# The image of crew.remote's end-to-end tests, locally (../local) and on AWS
# (../aws): R, targets and crew.remote's dependencies, the AWS command line
# tool, curl, and crew.remote itself from this checkout. GitHub Actions
# builds it for every commit on main and publishes it as
# ghcr.io/dm-k1/crew.remote-test:sha-<commit> (.github/workflows/test-image.yaml),
# so the machines of the AWS test start without installing anything.
FROM rocker/r-ver:4.6.1
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
      curl libglpk40 python3-pip procps > /dev/null \
 && pip install --quiet --break-system-packages awscli \
 && rm -rf /var/lib/apt/lists/*
RUN Rscript -e 'options(repos = c(CRAN = "https://p3m.dev/cran/__linux__/noble/latest")); install.packages(c("targets", "crew", "nanonext", "parallelly", "processx", "R6"))'
COPY . /src
RUN R CMD INSTALL /src > /dev/null
WORKDIR /src
