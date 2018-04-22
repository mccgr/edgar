library(rvest)
library(lubridate)
library(dplyr, warn.conflicts = FALSE)
library(tidyr)
library(RPostgreSQL)

# Create functions to get filings ----
getSECIndexFile <- function(year, quarter) {

    library(curl)
    library(readr)

    # Download the zipped index file from the SEC website
    tf <- tempfile(fileext = ".gz")
    result <- try(curl_download(
        url=paste("https://www.sec.gov/Archives/edgar/full-index/",
                  year,"/QTR", quarter, "/company.gz",sep=""),
        destfile=tf))

    # If we didn't encounter and error downloading the file, parse it
    # and return as a R data frame
    if (!inherits(result, "try-error")) {

        # Parse the downloaded file and return the extracted data as a data frame
        temp <-
            read_fwf(tf, fwf_cols(company_name = c(1,62),
                                  form_type = c(63,74),
                                  cik = c(75,86),
                                  date_filed = c(87,98),
                                  file_name = c(99,150)),
                     col_types = "ccicc", skip=10,
                     locale = locale(encoding = "macintosh")) %>%
            mutate(date_filed = as.Date(date_filed))
        return(temp)
    } else {
        return(NULL)
    }
}

addIndexFileToDatabase <- function(data) {
    if (is.null(data)) return(NULL)
    library(RPostgreSQL)
    pg <- dbConnect(PostgreSQL())

    # rs <- dbGetQuery(pg, "CREATE SCHEMA IF NOT EXISTS edgar")

    rs <- dbWriteTable(pg, c("edgar", "filings"), data,
                       append=TRUE, row.names=FALSE)

    rs <- dbGetQuery(pg, "ALTER TABLE edgar.filings OWNER TO edgar")
    rs <- dbGetQuery(pg, "GRANT SELECT ON TABLE edgar.filings TO edgar_access")
    comment <- 'CREATED USING get_filings_full.R/get_filings_incremental.R IN iangow-public/edgar'
    db_comment <- paste0("COMMENT ON TABLE edgar.filings IS '",
                         comment, " ON ", Sys.time() , "'; ")
    dbGetQuery(pg, db_comment)
    dbDisconnect(pg)
    return(rs)
}

deleteIndexDataFomDatabase <- function(pg, year, quarter) {
    if(dbExistsTable(pg, c("edgar", "filings"))) {
        dbGetQuery(pg, paste(
            "DELETE
            FROM edgar.filings
            WHERE extract(quarter FROM date_filed)=", quarter,
            " AND extract(year FROM date_filed)=", year))
    }
}

# Function to delete and then enter updated data for a given year and quarter
updateData <- function(pg, year, quarter) {

    cat("Updating data for ", year, "Q", quarter, "...\n", sep="")
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
pg <- dbConnect(PostgreSQL())

rs <- dbExecute(pg, "SET search_path TO edgar, public")

dbWriteTable(pg, "index_last_modified_new", index_last_modified_scraped,
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
    index_last_modified_scraped %>%
        mutate(last_modified = as.POSIXct(NA)) %>%
        dbWriteTable(pg, "index_last_modified", .,
             row.names = FALSE, overwrite = TRUE)

    to_update <-
        index_last_modified_scraped
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

dbExecute(pg, "DROP TABLE IF EXISTS index_last_modified_new")

dbDisconnect(pg)
