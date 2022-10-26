library(logdriver)
library(aptafford)
#* Confirm Vm is running
#* @get /status
function(){
  list(timestamp = Sys.time(),
    status = "OK")
}

#*  Show crontab logs
#* @get /cronlogs
function(){
  if (file.exists("/var/log/cron.log")){
    result <- readLines("/var/log/cron.log")
  } else {
    result <- "No logs found."
  }

  list(timestamp = Sys.time(),
       result = result)
}


#*  Show R session info
#* @get /sessioninfo
function(){

  list(timestamp = Sys.time(),
       result = utils::sessionInfo())
}
