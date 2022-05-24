#!/usr/bin/env Rscript
library(lubridate, warn.conflicts = FALSE)
library(dplyr, warn.conflicts = FALSE)
library(tidyr)
library(httr)
library(readr, warn.conflicts = FALSE)
library(DBI)
library(rvest)

ua <- "iandgow@gmail.com"

# Create functions to get filings ----
getSECIndexFile <- function(year, quarter) {

    # Download the zipped index file from the SEC website
    url <- paste0("https://www.sec.gov/Archives/edgar/full-index/",
                  year,"/QTR", quarter, "/company.gz")
    # Query webpage with default user agent
    t <- tempfile(fileext = ".gz")
    result <- try(GET(url, write_disk(t, overwrite=TRUE), user_agent(ua)))

    # If we didn't encounter and error downloading the file, parse it
    # and return as a R data frame
    if (!inherits(result, "try-error")) {

        # Parse the downloaded file and return the extracted data as a data frame
        temp <-
            read_fwf(t, fwf_cols(company_name = c(1, 62),
                                  form_type = c(63, 74),
                                  cik = c(75, 86),
                                  date_filed = c(87, 98),
                                  file_name = c(99, 150)),
                     col_types = "ccicc", skip=10,
                     locale = locale(encoding = "macintosh")) %>%
            mutate(date_filed = as.Date(date_filed))
        temp
    } else {
        NULL
    }
}

addIndexFileToDatabase <- function(data) {
    if (is.null(data)) return(NULL)
    pg <- dbConnect(RPostgres::Postgres())

    dbExecute(pg, "SET search_path TO edgar")

    rs <- dbWriteTable(pg, "filings", data,
                       append = TRUE, row.names = FALSE)

    rs <- dbExecute(pg, "ALTER TABLE filings OWNER TO edgar")
    rs <- dbExecute(pg, "GRANT SELECT ON TABLE filings TO edgar_access")
    comment <- 'CREATED USING get_filings.R IN mccgr/edgar'
    db_comment <- paste0("COMMENT ON TABLE filings IS '",
                         comment, " ON ", Sys.time() , "'; ")
    dbExecute(pg, db_comment)
    dbDisconnect(pg)
    return(rs)
}

deleteIndexDataFromDatabase <- function(pg, year, quarter) {
    dbExecute(pg, "SET search_path TO edgar")

    if(dbExistsTable(pg, "filings")) {
        dbExecute(pg, paste(
            "DELETE
            FROM filings
            WHERE extract(quarter FROM date_filed)=", quarter,
            " AND extract(year FROM date_filed)=", year))
    }
}

# Function to delete and then enter updated data for a given year and quarter
updateData <- function(pg, year, quarter) {

    dbExecute(pg, "SET search_path TO edgar")
    cat("Updating data for ", year, "Q", quarter, "...\n", sep="")
    try({
        deleteIndexDataFromDatabase(pg, year, quarter)
        dbExecute(pg, paste0("DELETE FROM index_last_modified WHERE year=", year,
                                   " AND quarter=", quarter))
        file <- getSECIndexFile(year, quarter)
        addIndexFileToDatabase(file)
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
    g <- GET(url, user_agent(ua))
    content(g, encoding = "UTF-8") %>%
        html_elements("table") %>%
        .[[1]] %>%
        html_table() %>%
        filter(Name == "company.gz") %>%
        select(`Last Modified`) %>%
        mdy_hms(tz = "America/New_York")
}

# Create table with last_modified ----
# Wait a day before trying to get data for a quarter.
now <- now(tz = 'America/New_York') - days(1)
current_year <- as.integer(year(now))
current_qtr <- quarter(now)
year <- 1993L:current_year
quarter <- 1:4L

index_last_modified_scraped <-
    crossing(year, quarter) %>%
    filter(year < current_year |
               (year == current_year & quarter <= current_qtr)) %>%
    rowwise() %>%
    mutate(last_modified = getLastUpdate(year, quarter))

# Push results to database ----
pg <- dbConnect(RPostgres::Postgres())

rs <- dbExecute(pg, "SET search_path TO edgar")
if (!length(dbListTables(pg))) {
    try(rs <- dbExecute(pg, "CREATE SCHEMA edgar"))
    try(rs <- dbExecute(pg, "CREATE ROLE edgar"))
    try(rs <- dbExecute(pg, "CREATE ROLE edgar_access"))
    rs <- dbExecute(pg, "ALTER SCHEMA edgar OWNER TO edgar")
    rs <- dbExecute(pg, paste("GRANT edgar TO", DBI::dbGetInfo(pg)$username))
}
rs <- dbWriteTable(pg, "index_last_modified_new", index_last_modified_scraped,
             row.names = FALSE, overwrite = TRUE)

# Compare new data with old to identify needed index files ----
if (dbExistsTable(pg, "index_last_modified")) {

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
    index_last_modified_scraped %>%
        mutate(last_modified = as.POSIXct(NA)) %>%
        dbWriteTable(pg, "index_last_modified", .,
             row.names = FALSE, overwrite = TRUE)

    to_update <-
        index_last_modified_scraped
}

#
# If to_update has a non-trivial number of observations/rows (ie. at least 1),
# update the data.
if(nrow(to_update) > 0) {
    to_update <-
        to_update %>%
        rowwise() %>%
        mutate(updated = updateData(pg, year, quarter))
}

rs <- dbExecute(pg, "ALTER TABLE filings OWNER TO edgar")
rs <- dbExecute(pg, "GRANT SELECT ON filings TO edgar_access")
rs <- dbExecute(pg, "ALTER TABLE index_last_modified OWNER TO edgar")
rs <- dbExecute(pg, "GRANT SELECT ON index_last_modified TO edgar_access")
rs <- dbExecute(pg, "DROP TABLE IF EXISTS index_last_modified_new")
comment <- 'CREATED USING get_filings.R IN mccgr/edgar'
db_comment <- paste0("COMMENT ON TABLE filings IS '",
                     comment, " ON ", Sys.time() , "'")
rs <- dbExecute(pg, db_comment)

rs <- dbDisconnect(pg)
