# ONS / CITY OF OTTAWA APARTMENT AFFORDABILITY PROJECT
#
# Code to consolidate daily rental unit data from four sources in the PostgresQL
# server and create a new table of daily cleaned data.
# Can be run through a cron job.

## Setup ----

library(dplyr, warn.conflicts = FALSE)
library(dbplyr, warn.conflicts = FALSE)
library(DBI)
library(RPostgres)
library(promises)
library(future)
library(logdriver)
library(plumber)
#library(sf)

Sys.setenv('LOGDRIVER_HOST'='logdriver-test.fly.dev')
Sys.setenv('LOGDRIVER_PORT'='8000')
Sys.setenv('LOGDRIVER_APPNAME'='aptafford_project')

username <- "ingest"

# sudo wg-quick up wg_aptafford
db_url <- "aptafford-db.internal"

db_password <- 'e99b504fe94d80decadd966910b2065a0f4c540dedab90f9'

## Functions ----


## Get data from database ----
weekly_update <- tryCatch ({

  con <- DBI::dbConnect(RPostgres::Postgres(),dbname = 'postgres',
                        host = db_url,
                        port = 5432,
                        user = 'postgres',
                        password = db_password)

  # DBI::dbListTables(con)
  # test <- dplyr::tbl(con, "longterm_results")
  # test %>% summarise(n=n())

  # if table doesn't exist yet, create it.
  # if it does exist, append the most recent data.
  # we only use some of the columns for privacy and data size.
  if (!"longterm_results" %in% DBI::dbListTables(con)) {

    DBI::dbExecute(con,
    'CREATE TABLE "longterm_results"
     AS SELECT   "property_type", "bedrooms", "bathrooms", "rent",
                 "date_scraped", "source", "ONS_ID_gen2", "ONS_ID_gen3"
     FROM "daily_results";')

  } else {

    DBI::dbExecute(con,
    'INSERT INTO "longterm_results"
     SELECT  "property_type", "bedrooms", "bathrooms", "rent",
             "date_scraped", "source", "ONS_ID_gen2", "ONS_ID_gen3"
     FROM "daily_results";')
  }

  DBI::dbDisconnect(con)

  TRUE
}, error = function(e) {print(e); e})

if ("error" %in% class(weekly_update)){
  logdriver::add_log(level = "critical", event = "Long-term storage: Failed weekly database update.", username = username)
  stop("Long-term storage: Failed weekly database update")
} else {
  logdriver::add_log(level = "info", event = "Long-term storage: Success weekly updating database.", username = username)
}

