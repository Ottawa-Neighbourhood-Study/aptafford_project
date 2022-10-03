FROM rhub/r-minimal

RUN apk add --no-cache gcc musl-dev g++ \
libsodium-dev curl-dev linux-headers autoconf automake libsodium \
libxml2-dev libxml2 \
postgresql-dev && \
R -q -e 'install.packages(c("plumber", "dplyr", "dbplyr", "DBI", "promises", "future","lubridate", "RPostgres", "fastmap", "stringr", "httr", "remotes", "rvest"), repos = "https://cloud.r-project.org")' && \
rm -rf /usr/local/lib/R/library/*/html && \
rm -rf /usr/local/lib/R/library/*/doc && \
rm -rf /usr/local/lib/R/library/*/help && \
apk del gcc musl-dev g++ linux-headers autoconf


RUN installr -c && \
R -q -e 'remotes::install_github("https://github.com/chris31415926535/logdriver")' && \
rm -rf /usr/local/lib/R/library/*/html && \
rm -rf /usr/local/lib/R/library/*/doc && \
rm -rf /usr/local/lib/R/library/*/help && \
apk del gcc musl-dev g++

RUN apk add gcc musl-dev g++ linux-headers autoconf  && \
R -q -e 'remotes::install_github("https://github.com/Ottawa-Neighbourhood-Study/aptafford")' && \
apk del gcc musl-dev g++ linux-headers autoconf

COPY . .

# PUT SCHEDULED SCRIPTS INTO THE CORRECT CRON FOLDER TO RUN REGULARLY
#RUN cp cron/* /etc/periodic/hourly
#RUN cp cron/* /etc/periodic/15min
RUN cp cron/* /etc/periodic/daily

EXPOSE 8080

# Run cron in the background, run plumber API for status and debug log checks in the foreground
CMD crond -l 0 -L /var/log/cron.log && R -q -e 'plumber::pr_run(plumber::pr("R/plumber_ingest.R"), port=8080, host = "0.0.0.0")'
