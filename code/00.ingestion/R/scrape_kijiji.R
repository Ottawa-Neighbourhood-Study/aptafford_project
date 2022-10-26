# ONS / CITY OF OTTAWA APARTMENT AFFORDABILITY PROJECT
#
# Code to collect daily rental unit data from Kijiji and push it to
# PostgreSQL server.
# Can be run through a cron job.


library(magrittr)
library(dplyr, warn.conflicts = FALSE)
library(aptafford)
library(logdriver)
library(DBI)
library(RPostgres)
#library(purrr)
#library(readr)

Sys.setenv('LOGDRIVER_HOST'='logdriver-test.fly.dev')
Sys.setenv('LOGDRIVER_PORT'='8000')
Sys.setenv('LOGDRIVER_APPNAME'='aptafford_project')

# localhost if proxying, aptafford-db.internal in production and with wireguard setup
db_url <- "localhost"
db_url <- "aptafford-db.internal"

db_name <- "kijiji_new"

db_password <- 'e99b504fe94d80decadd966910b2065a0f4c540dedab90f9'

appname <- "aptafford_ingestion"
username <- "ingest"


logdriver::add_log(level = "info", event = "Kijiji: Begin scraping", username = username)

scrape_attempt <- 1

for (scrape_attempt in 1:5){
  scrape_success <- FALSE

  newdata <- tryCatch(aptafford::kijiji_scrape(num_pages = 40),
                      error = function(e) e)

  # we have succeeded if we get a tibble
  if ((!"error" %in% colnames(newdata)) & (!all(is.null(newdata))) ) scrape_success <- TRUE

  if (scrape_success == TRUE) break

  logdriver::add_log(level = "critical", event = sprintf("Kijiji: Scraping attempt #%s failed", scrape_attempt), username = username,
                     description = substring(paste0(as.character(head(newdata)), collapse=""), first=1, last = 200))

}

logdriver::add_log( event = "Kijiji: Scraping complete",
                    description = sprintf("nrows=%s", nrow(newdata)), username = username)

newdata$date_scraped <- Sys.time()

table_write <- tryCatch ({
  con <- DBI::dbConnect(RPostgres::Postgres(),dbname = 'postgres',
                        host = db_url, # i.e. 'ec2-54-83-201-96.compute-1.amazonaws.com'
                        port = 5432, # or any other port specified by your DBA
                        user = 'postgres',
                        password = db_password)

  #DBI::dbListTables(con)
  # dplyr::select(dplyr::tbl(con, "realtorca_new"), date_scraped)
  dplyr::copy_to(con, newdata, name = db_name, overwrite = TRUE,  temporary = FALSE )
  DBI::dbDisconnect(con)
}, error = function(e) {print(e); e})

if ("error" %in% class(table_write)){
  logdriver::add_log(level = "critical", event = "Kijiji: Failed to write data to database.", username = username)
} else {
  logdriver::add_log(level = "info", event = "Kijiji: Success writing data to database.", username = username)
}
