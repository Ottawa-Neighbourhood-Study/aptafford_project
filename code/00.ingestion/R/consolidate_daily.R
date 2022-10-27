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
library(sf)

Sys.setenv('LOGDRIVER_HOST'='logdriver-test.fly.dev')
Sys.setenv('LOGDRIVER_PORT'='8000')
Sys.setenv('LOGDRIVER_APPNAME'='aptafford_project')

username <- "ingest"

# sudo wg-quick up wg_aptafford
db_url <- "aptafford-db.internal"

db_password <- 'e99b504fe94d80decadd966910b2065a0f4c540dedab90f9'

ons_shp_gen2 <- sf::read_sf("data/ons_shp_gen2/ons_shp_gen2.shp") %>%
  sf::st_transform(crs = 32189) %>%
  dplyr::select(ONS_ID_gen2 = ONS_ID, ONS_Name_gen2 = Name)

ons_shp_gen3 <- sf::read_sf("data/ons_shp_gen3/Final_Gen3_Sep2022.shp") %>%
  # dplyr::filter(ONS_Region == "OTTAWA" ) %>%
  sf::st_transform(crs = 32189) %>%
  dplyr::select(ONS_ID_gen3 = ONS_ID, ONS_Name_gen3 = ONS_Name)

## Functions ----

# take df with lat/lon coords, convert to NAD shapefile
add_nad_sf <- function(df) {

  df %>%
    sf::st_as_sf(coords = c("lon", "lat"),  crs = "WGS84", remove  = FALSE) %>%
    sf::st_transform(crs = 32189)
}

# define function to remove apartments within 50m of old apartments
remove_geo_overlaps <- function(old_data, new_data, radius_metres = 50){
  geomask <- old_data %>%
    sf::st_buffer(dist = 50) %>%
    sf::st_union()

  to_add <- new_data %>%
    dplyr::filter(!sf::st_intersects(geometry, geomask, sparse = FALSE))

  result <- dplyr::bind_rows(old_data, to_add)

  return(result)
}


## Get data from database ----
table_read <- tryCatch ({
  con <- DBI::dbConnect(RPostgres::Postgres(),dbname = 'postgres',
                        host = db_url,
                        port = 5432,
                        user = 'postgres',
                        password = db_password)

  rn <- dplyr::tbl(con, "rentalsca_new") %>% dplyr::collect()
  re <- dplyr::tbl(con, "realtorca_new") %>% dplyr::collect()
  pm <- dplyr::tbl(con, "padmapper_new") %>% dplyr::collect()
  kj <- dplyr::tbl(con, "kijiji_new")    %>% dplyr::collect()

  DBI::dbDisconnect(con)

  TRUE
}, error = function(e) {print(e); e})

if ("error" %in% class(table_read)){
  logdriver::add_log(level = "critical", event = "Consolidation: Failed reading from database.", username = username)
  stop("Consolidation: Failed reading from database.")
} else {
  logdriver::add_log(level = "info", event = "Consolidation: Success reading from database.", username = username)
}



## Clean daily data ----

cleandata_try <- tryCatch({

  ### rentals.ca ----

  rentalsca_clean <- rn %>%
    dplyr::mutate(unique_id = sprintf("rn-%s-%s", location_id, id)) %>%
    dplyr::select(title, property_type, bedrooms, bathrooms, rent, address = address1,
                  lat, lon = lng, unique_id, url, date_scraped) %>%
    dplyr::mutate(source = "rentals.ca")

# also! rentals.ca includes some house duplicates: houses and townhouses listed more than once. here we clear them out
  rentalsca_clean <- rentalsca_clean %>%
    dplyr::mutate(house = stringr::str_detect(property_type,  "house")) %>%
    dplyr::group_by(address, bedrooms, bathrooms, rent) %>%
    dplyr::mutate(n=n()) %>%
    dplyr::mutate(house_count = if_else(house, n, 1L)) %>%
    dplyr::mutate(need_trim = house_count > 1) %>%
    tidyr::nest(data = -need_trim) %>%
    dplyr::mutate(data = if_else(need_trim, purrr::map(data, slice_head, n=1), data)) %>%
    tidyr::unnest(cols = "data") %>%
    dplyr::select(-need_trim, -house, -n, -house_count) %>%
    add_nad_sf() %>%
    dplyr::mutate(dplyr::across(-"geometry", as.character))


  ### realtor.ca ----

  realtorca_clean <- re %>%
    mutate(unique_id = sprintf("rl-%s-%s",mls_number, id)) %>%
    mutate(url = paste0("https://www.realtor.ca", relative_url_en)) %>%
    select(title = public_remarks, property_type, bedrooms = building_bedrooms,
           bathrooms = building_bathroom_total, rent = property_lease_rent_unformatted_value, address = property_address_address_text,
           lat = property_address_latitude, lon = property_address_longitude, unique_id, url, date_scraped) %>%
    mutate(title = strtrim(title, width = 100),
           bedrooms = as.numeric(stringr::str_extract(bedrooms, "\\d")),
           source = "realtor.ca") %>%
    add_nad_sf() %>%
    dplyr::mutate(dplyr::across(-"geometry", as.character))


  ### padmapper ----

  if (!"url" %in% colnames(pm)){

    pm <- pm %>%
      dplyr::mutate(url = dplyr::if_else(
        is.na(pb_id),
        paste0("https://www.padmapper.com/apartments/",pl_id,"p"),
        paste0("https://www.padmapper.com/buildings/p", pb_id)
      ))
  }

  # padmapper does not always give titles, so if there is no title we give the address
  padmapper_clean <- pm %>%
    dplyr::mutate(unique_id = sprintf("pm-%s-%s", building_id, listing_id)) %>%
    dplyr::select(title = building_name, bedrooms, bathrooms = bathrooms, rent = price,
                  address = address, lat = lat, lon = lng, unique_id, url, date_scraped) %>%
    dplyr::mutate(title = strtrim(title, width = 100),
                  source = "padmapper") %>%
    dplyr::mutate(title = dplyr::if_else(is.na(title), address, title)) %>%
    add_nad_sf() %>%
    dplyr::mutate(dplyr::across(-"geometry", as.character))



  ### Kijiji ----

  kijiji_clean <- kj %>%
    mutate(unique_id  = paste0("kj-", stringr::str_extract(url, "(?<=/)\\d+$"))) %>%
    select(title, bedrooms, bathrooms, property_type = unit_type,
           rent = price, address = address, lat = lat, lon = lon, unique_id, url, date_scraped) %>%
    distinct(title, bedrooms, .keep_all = TRUE) %>%
    mutate(bedrooms = dplyr::if_else(stringr::str_detect(bedrooms, "Bachelor"), "0", bedrooms),
           bedrooms = as.numeric(stringr::str_extract(bedrooms, "\\d"))) %>%
    mutate(source = "kijiji") %>%
    add_nad_sf() %>%
    dplyr::mutate(dplyr::across(-"geometry", as.character))

  TRUE
}, error = function(e) {print(e); e})


if ("error" %in% class(cleandata_try)){
  logdriver::add_log(level = "critical", event = "Consolidation: Failed to clean data.", username = username)
  stop("Consolidation: Failed to clean data.")
} else {
  logdriver::add_log(level = "info", event = "Consolidation: Success cleaning data.", username = username)
}

## Consolidate ----

# we start with rentals.ca data, then add sources one by one, keeping only results
# that are not within 50m of a previous result to avoid duplicates.
# we clean each data source individually to remove within-source duplicates
# then rely on geographic boundaries to avoid inter-source duplicates
# we also filter out vacant land, and rents under 10$ and over 10,000$
# we combine a few categories from different sources (e.g. "duplex" -> "duplex/triplex")

consolidation <- tryCatch({
  rentalsca_clean %>%
    remove_geo_overlaps(padmapper_clean) %>%
    remove_geo_overlaps(realtorca_clean) %>%
    remove_geo_overlaps(kijiji_clean) %>%
    sf::st_join(ons_shp_gen2) %>%
    sf::st_join(ons_shp_gen3) %>%
    sf::st_set_geometry(NULL) %>%
    dplyr::mutate(dplyr::across(dplyr::everything(), as.character),
      bedrooms = as.numeric(bedrooms),
                  bathrooms = as.numeric(bathrooms),
                  rent = as.numeric(rent)) %>%
    dplyr::filter(!property_type %in% "Vacant Land") %>%
    dplyr::mutate(property_type = dplyr::if_else(is.na(property_type), "unspecified", tolower(property_type))) %>%
    dplyr::filter(as.numeric(rent) > 10,
           as.numeric(rent) < 10000) %>%
    dplyr::mutate(property_type = dplyr::case_when(
      property_type == "duplex" ~ "duplex/triplex",
      property_type == "town house" ~ "townhouse"
    ))

}, error = function(e) {print(e); e})


if ("error" %in% class(consolidation)){
  logdriver::add_log(level = "critical", event = "Consolidation: Failed combine data sources.", username = username)
  stop("Consolidation: Failed combine data sources.")
} else {
  logdriver::add_log(level = "info", event = "Consolidation: Success combining data sources.", username = username)
}

## Write to database ----

table_write <- tryCatch ({
  con <- DBI::dbConnect(RPostgres::Postgres(),dbname = 'postgres',
                        host = db_url,
                        port = 5432,
                        user = 'postgres',
                        password = db_password)


  dplyr::copy_to(con, consolidation, name = "daily_results", overwrite = TRUE,  temporary = FALSE )
  DBI::dbDisconnect(con)
}, error = function(e) {print(e); e})

if ("error" %in% class(table_write)){
  logdriver::add_log(level = "critical", event = "Consolidation: Failed to write data to database.", username = username)
  stop("Consolidation: Failed to write data to database.")
} else {
  logdriver::add_log(level = "info", event = "Consolidation: Success writing data to database.", username = username)
}


