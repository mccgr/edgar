library(rvest)
library(lubridate)
library(dplyr, warn.conflicts = FALSE)
library(tidyr)
library(RPostgreSQL)


#### import functions which read and delete data to database from 'get_filings.function.R'
source('get_filings_function.R')

# Function to delete and then enter updated data for a given year and quarter
updateData <- function(pg, year, quarter) {

    try({deleteIndexDataFomDatabase(pg, year, quarter); addIndexFileToDatabase(getSECIndexFile(year, quarter)); return(TRUE)}, return(FALSE))

}


# Function to last modified data from EDGAR ----
getLastUpdate <- function(year, quarter) {

    url <- paste0("https://www.sec.gov/Archives/edgar/full-index/",
                 year, "/QTR", quarter, "/")

    # Scrape the html table from the website for the given year and quarter
    read_html(url) %>%
        html_nodes("table") %>%
        .[[1]] %>%
        html_table() %>%
        filter(Name == "company.gz") %>%
        select(`Last Modified`) %>%
        mdy_hms(tz = "America/New_York")
}

# Create table with last_modified ----
now <- now(tz = 'America/New_York')
current_year <- year(now)
current_qtr <- quarter(now)
year <- 1993:current_year
quarter <- 1:4L

index_last_modified_new <-
    crossing(year, quarter) %>%
    filter(year < current_year |
               (year == current_year & quarter <= current_qtr)) %>%
    rowwise() %>%
    mutate(last_modified = getLastUpdate(year, quarter))

# Push results to database ----
pg <- dbConnect(PostgreSQL())

rs <- dbExecute(pg, "SET search_path TO edgar, public")


# Compare new data with old to identify needed index files ----
if (dbExistsTable(pg, "index_last_modified")) {
    index_last_modified <- dbGetQuery(pg, "SELECT * FROM index_last_modified;")


    # Use force_tz to ensure the correct times in EDT. Database stores times in Melbourne time, convert to New York time before comparison

    index_last_modified$last_modified <- with_tz(index_last_modified$last_modified, tz = "America/New_York")

    to_update <- index_last_modified_new %>%
        left_join(index_last_modified,
                  by = c("year", "quarter"),
                  copy = TRUE,
                  suffix = c("_new", "_old")) %>%
        filter(is.na(last_modified_old) |
                   last_modified_new > last_modified_old) %>%
        collect()
} else {
    to_update <-
        index_last_modified_new %>%
        collect()
}

####
#
#  Insert code to update data using to_update here.
#  The rowwise() %>% mutate() model probably works,
#  as the function used in mutate() could have the side-effect
#  of updating the table.
#
# If to_update has a non-trivial number of observations/rows (ie. at least 1), update the data
#
if(dim(to_update)[1] > 0) {

    to_update <- to_update %>% rowwise() %>% mutate(updated = updateData(pg, year, quarter))

}



####


# Convert index_last_modified_new to AEST (or local timezone) before storing in database, as the SQL database naturally stores dates in local time.

index_last_modified_new$last_modified <- with_tz(index_last_modified_new$last_modified, tz = Sys.timezone())


# Put/update index_last_modified in database


rs <- dbWriteTable(pg, "index_last_modified",
             index_last_modified_new,
             row.names = FALSE,
             overwrite = TRUE)

dbDisconnect(pg)


