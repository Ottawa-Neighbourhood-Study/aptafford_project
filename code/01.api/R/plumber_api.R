# ONS / CITY OF OTTAWA APARTMENT AFFORDABILITY PROJECT
#
# Plumber API for data and analytics out.
# Pulls from PostgreSQL server.
# Should be hosted on fly.io

library(dplyr, warn.conflicts = FALSE)
library(dbplyr, warn.conflicts = FALSE)
library(DBI)
library(RPostgres)
library(promises)
library(future)
library(logdriver)
library(plumber)

# Sys.setenv('LOGDRIVER_HOST'='logdriver-test.fly.dev')
# Sys.setenv('LOGDRIVER_PORT'='8000')
# Sys.setenv('LOGDRIVER_APPNAME'='aptafford_project')

username <- "api"


#* @apiTitle Ottawa/ONS Apartment Affordability Project: Data Out
#* @apiDescription Get data about apartment availability and affordability in
#*                 Ottawa, Ontario.

future::plan(future::multisession())

db_url <- "aptafford-db.internal"

db_password <- 'e99b504fe94d80decadd966910b2065a0f4c540dedab90f9'

#* Get daily apartment listings from various sources.
#*
#* This is where a longer description would go.
#*
#* @param source The data source. "rentalsca" for Rentals.ca, "realtorca" for Realtor.ca.
#* @get /daily_units
#* @response 200 A dataframe of apartment data.
function(source) {

  # TODO FIXME input  validation
  if (! source %in% c("rentalsca", "realtorca")) stop ("Invalid source. Accepted values are 'rentalsca' and 'realtorca'.")
  db_name <- paste0(source, "_new")

  # we do the whole thing in a future_promise for concurrency
  result <- promises::future_promise({

    con <- DBI::dbConnect(RPostgres::Postgres(),
                          dbname = 'postgres',
                          host = db_url,#'localhost', # i.e. 'ec2-54-83-201-96.compute-1.amazonaws.com'
                          port = 5432, # or any other port specified by your DBA
                          user = 'postgres',
                          password = db_password)

    # FIXME check that db connection is valid
    if (!DBI::dbIsValid(con)){
      logdriver::add_log(event_level = "critical", event = "API Query failure", description = "Cannot connect to database", username = username)
      return(NULL)
    }

    # get pointer to specific table in the database
    db_values <- dplyr::tbl(con, db_name)



    # if (!all(is.na(cylinders))){
    #   result <- result %>%
    #     dplyr::filter(cyl %in% cylinders) # %in% works for numeric!!
    #   #dplyr::filter(cyl %like% cylinders) # this is for regexes I think https://www.prisma.io/dataguide/postgresql/reading-and-querying-data/filtering-data
    # }
    #
    # if (!all(is.na(min_hp))){
    #   result <- result %>%
    #     dplyr::filter(hp >= min_hp)
    # }

    result <- dplyr::collect(db_values)

    logdriver::add_log(event = "API query successful", description = sprintf("source=%s", db_name), username = username)

    DBI::dbDisconnect(con)

    result
  })

  return(result)
}