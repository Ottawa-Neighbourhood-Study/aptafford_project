# ONS / CITY OF OTTAWA APARTMENT AFFORDABILITY PROJECT
#
# Code to collect daily rental unit data from Rentals.ca and push it to
# PostgreSQL server.
# Can be run through a cron job.

library(aptafford)
library(logdriver)

library(dplyr, warn.conflicts = FALSE)
library(DBI)
library(RPostgres)
#library(promises)
#library(future)

Sys.setenv('LOGDRIVER_HOST'='logdriver-test.fly.dev')
Sys.setenv('LOGDRIVER_PORT'='8000')
Sys.setenv('LOGDRIVER_APPNAME'='aptafford_project')



# FOR LOCAL TESTING, CREATE A PROXY CONNECTION TO THE DATABASE.
# flyctl proxy 5432 -a aptafford-db
# OR USE WIREGUARD.
# wg-quick up wg_aptafford

# localhost if proxying, aptafford-db.internal in production and with wireguard setup
db_url <- "localhost"
db_url <- "aptafford-db.internal"

#appname <- "aptafford_ingestion"
username <- "ingest"


logdriver::add_log(level = "info", event = "Rentals.ca: Begin scraping", username = username)

# for small testing set, add "cumberland-on" as parameter to aptafford::rentalsca_scrape()
newdata <- tryCatch (aptafford::rentalsca_scrape(),
                           error = function(e) e )

if ("error" %in% class(newdata)){
  logdriver::add_log(level = "critical", event = "Rentals.ca: Scraping failed", username = username)
  return(0)
}

logdriver::add_log(event = "Rentals.ca: Scraping complete",
                   description = sprintf("nrows=%s", nrow(newdata)), username = username)

newdata$date_scraped <- Sys.time()


table_write <- tryCatch ({
  con <- DBI::dbConnect(RPostgres::Postgres(),dbname = 'postgres',
                        host = db_url, # i.e. 'ec2-54-83-201-96.compute-1.amazonaws.com'
                        port = 5432, # or any other port specified by your DBA
                        user = 'postgres',
                        password = 'e99b504fe94d80decadd966910b2065a0f4c540dedab90f9')

  # dplyr::select(dplyr::tbl(con, "rentalsca_new"), date_scraped)
  dplyr::copy_to(con, newdata, name = "rentalsca_new", overwrite = TRUE,  temporary = FALSE )
  DBI::dbDisconnect(con)
}, error = function(e) {print(e); e})

if ("error" %in% class(table_write)){
  logdriver::add_log(level = "critical", event = "Rentals.ca: Failed to write data to database.", username = username)
} else {
  logdriver::add_log(level = "info", event = "Rentals.ca: Success writing data to database.", username = username)
}
