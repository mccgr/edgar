library(rvest)
library(lubridate)
library(dplyr, warn.conflicts = FALSE)
library(tidyr)
library(RPostgreSQL)

# Import functions which read and delete data ----
source('get_filings_function.R')

# Function to delete and then enter updated data for a given year and quarter
updateData <- function(pg, year, quarter) {

    try({
        deleteIndexDataFomDatabase(pg, year, quarter)
        dbExecute(pg, paste0("DELETE FROM index_last_modified WHERE year=", year,
                                   " AND quarter=", quarter))
        addIndexFileToDatabase(getSECIndexFile(year, quarter))
        dbExecute(pg, paste0("INSERT INTO index_last_modified ",
                                   "SELECT * FROM index_last_modified_new WHERE year=", year,
                                   " AND quarter=", quarter))
        return(TRUE)
        },
        return(FALSE))
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

dbWriteTable(pg, "index_last_modified_new", index_last_modified_new,
             row.names = FALSE, overwrite = TRUE)

# Compare new data with old to identify needed index files ----
if (dbExistsTable(pg, c("edgar", "index_last_modified"))) {
    index_last_modified_new <- tbl(pg, "index_last_modified_new")
    index_last_modified <- tbl(pg, "index_last_modified")

    # Use force_tz to ensure the correct times in EDT.
    # Database stores times in UTC

    to_update <-
        index_last_modified_new %>%
        left_join(index_last_modified,
                  by = c("year", "quarter"),
                  suffix = c("_new", "_old")) %>%
        filter(is.na(last_modified_old) |
                   last_modified_new > last_modified_old) %>%
        collect()
} else {
    to_update <-
        index_last_modified_new %>%
        collect()
}

#
# If to_update has a non-trivial number of observations/rows (ie. at least 1), update the data
#
if(nrow(to_update) > 0) {
    to_update <-
        to_update %>%
        rowwise() %>%
        mutate(updated = updateData(pg, year, quarter))
}

# Put/update index_last_modified in database
dbDisconnect(pg)
