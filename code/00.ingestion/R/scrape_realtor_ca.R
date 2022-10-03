# ONS / CITY OF OTTAWA APARTMENT AFFORDABILITY PROJECT
#
# Code to collect daily rental unit data from Realtor.ca and push it to
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

appname <- "aptafford_ingestion"
username <- "ingest"


logdriver::add_log(level = "info", event = "Realtor.ca: Begin scraping", username = username)

newdata <- tryCatch(aptafford::realtor_scrape(),
                    error = function(e) e)

if ("error" %in% colnames(newdata)){
  logdriver::add_log(level = "critical", event = "Realtor.ca: Scraping failed", username = username)
  return (0)
}

logdriver::add_log( event = "Realtor.ca: Scraping complete",
                    description = sprintf("nrows=%s", nrow(newdata)), username = username)

newdata$date_scraped <- Sys.time()

table_write <- tryCatch ({
  con <- DBI::dbConnect(RPostgres::Postgres(),dbname = 'postgres',
                        host = db_url, # i.e. 'ec2-54-83-201-96.compute-1.amazonaws.com'
                        port = 5432, # or any other port specified by your DBA
                        user = 'postgres',
                        password = 'e99b504fe94d80decadd966910b2065a0f4c540dedab90f9')

  #DBI::dbListTables(con)
  dplyr::copy_to(con, newdata, name = "realtorca_new", overwrite = TRUE,  temporary = FALSE )
  DBI::dbDisconnect(con)
}, error = function(e) {print(e); e})

if ("error" %in% class(table_write)){
  logdriver::add_log(level = "critical", event = "Realtor.ca: Failed to write data to database.", username = username)
} else {
  logdriver::add_log(level = "info", event = "Realtor.ca: Success writing data to database.", username = username)
}
