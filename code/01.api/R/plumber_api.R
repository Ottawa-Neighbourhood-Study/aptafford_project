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

Sys.setenv('LOGDRIVER_HOST'='logdriver-test.fly.dev')
Sys.setenv('LOGDRIVER_PORT'='8000')
Sys.setenv('LOGDRIVER_APPNAME'='aptafford_project')

username <- "api"


#* @apiTitle Ottawa/ONS Apartment Affordability Project: Data Out
#* @apiDescription Get data about apartment availability and affordability in
#*                 Ottawa, Ontario.

future::plan(future::multisession())


# for a bigger implementation would not store these values in the source code
db_url <- "aptafford-db.internal"

db_password <- 'e99b504fe94d80decadd966910b2065a0f4c540dedab90f9'
authorized_tokens <- c("56ab24c15b72a457069c5ea42fcfc640")


# Check bearer authorization against list of accepted tokens
check_auth <- function(req, res){

  token <- req$HTTP_AUTHORIZATION

  if (is.null(token)) token <- "nope"
  token <- tolower(token)

  # must include 'Bearer' in the token
  # remove whitespace
  if (!grepl(x=token, pattern="bearer")) token <- "nope"
  token <- gsub(x = token, pattern = "bearer", replacement = "")
  token <- gsub(x = token, pattern = "\\s", replacement = "")

  # debugging
  print(token)
  print(authorized_tokens)

  #  check against authorized token list
  if (!token %in% authorized_tokens) {
    res$status <- 403

    logdriver::add_log(level = "error" , event = "/authtest", description = "Failure: Unauthorized API call", username = username)

    stop("Unauthorized")
  }
}

#* testing bearer auth
#*
#* @get /authtest
function(req, res){


  # https://swagger.io/docs/specification/authentication/bearer-authentication/
  check_auth(req, res)

  # will only get here if token is in authorized_tokens
  response <- "Success"
  logdriver::add_log(level = "info" , event = "/authtest", description = "Success: Authorized API call", username = username)

  return (response)
}

#* Give basic health check--confirm API is working.
#*
#*
#* @get /status
#* @response 200 "OK"
function() {
 result <- list(status = "OK",
                timestamp = Sys.time())

 return(result)
}

#*  Show R session info
#* @get /sessioninfo
function(){

  s <- capture.output(print(sessionInfo()))

  s <- paste0(s, collapse = "\n")

  list(timestamp = Sys.time(),
       result = s)
}


#* Get daily apartment listings from various sources.
#*
#* This is where a longer description would go.
#*
#* @param source The data source, default is all daily consolidated values.
#* Accepted values "all", "rentalsca", "realtorca", "kijiji", "padmapper".
#*  "padmapper.
#* @get /daily_units
#* @response 200 A dataframe of apartment data.
function(req, res, source="all") {

  # TODO FIXME input  validation
  if (! source %in% c("all","kijiji","padmapper", "rentalsca", "realtorca")) stop ("Invalid source. Accepted values are 'rentalsca' and 'realtorca'.")

  db_name <- switch(source,
                    "all" = "daily_results",
                    "kijiji" = "kijiji_new",
                    "rentalsca" = "rentalsca_new",
                    "padmapper" = "padmapper_new",
                    "realtorca" = "realtorca_new")



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
      logdriver::add_log(level = "critical", event = "API Query failure", description = "Cannot connect to database", username = username)
      return(NULL)
    }

    # get pointer to specific table in the database
    db_values <- dplyr::tbl(con, db_name)

    result <- dplyr::collect(db_values)

    logdriver::add_log(event = "API query successful", description = sprintf("source=%s", db_name), username = username)

    DBI::dbDisconnect(con)

    result
  }, seed = TRUE)

  return(result)
}
