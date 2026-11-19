# The image for the local test: R, the packages, the AWS command line tool
# (talking to a local S3), curl, and crew.remote from this checkout
FROM rocker/r-ver:4.6.1
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
      curl libglpk40 python3-pip procps > /dev/null \
 && pip install --quiet --break-system-packages awscli \
 && rm -rf /var/lib/apt/lists/*
RUN Rscript -e 'options(repos = c(CRAN = "https://p3m.dev/cran/__linux__/noble/latest")); install.packages(c("targets", "crew", "nanonext", "parallelly", "processx", "R6"))'
COPY . /src
RUN R CMD INSTALL /src > /dev/null
WORKDIR /src
