FROM rhub/r-minimal

# Need https://github.com/tidyverse/readxl/pull/687 for readxl

RUN apk add linux-headers gfortran gcc musl-dev g++ curl-dev libxml2-dev linux-headers gfortran libcurl libxml2 &&  \
R -q -e 'install.packages("xml2", repos = "https://cloud.r-project.org")' && \
apk del linux-headers gfortran gcc musl-dev g++
#gaborcsardi/readxl@fix/alpine-linux tidyverse
