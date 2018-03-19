library(rvest)
library(lubridate)
library(dplyr, warn.conflicts = FALSE)
library(tidyr)
library(RPostgreSQL)

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
        mdy_hms(tz = "UTC")
}

# Create table with last_modified ----
now <- today(tz = "UTC")
current_year <- year(now)
current_qtr <- quarter(now)
year <- 1993:current_year
quarter <- 1:4L

index_last_modified <-
    crossing(year, quarter) %>%
    filter(year < current_year |
               (year == current_year & quarter <= current_qtr)) %>%
    rowwise() %>%
    mutate(last_modified = getLastUpdate(year, quarter))

# Push results to database ----
pg <- dbConnect(PostgreSQL())

rs <- dbExecute(pg, "SET search_path TO edgar, public")

rs <- dbWriteTable(pg, "index_last_modified_new",
             index_last_modified,
             row.names = FALSE,
             overwrite = TRUE)

index_last_modified_new <- tbl(pg, "index_last_modified_new")

# Compare new data with old to identify needed index files ----
if (dbExistsTable(pg, "index_last_modified")) {
    index_last_modified <- tbl(pg, "index_last_modified")

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

####
#
#  Insert code to update data using to_update here.
#  The rowwise() %>% mutate() model probably works,
#  as the function used in mutate() could have the side-effect
#  of updating the table.
#
####

rs <- dbWriteTable(pg, "index_last_modified",
             index_last_modified,
             row.names = FALSE,
             overwrite = TRUE)

dbDisconnect(pg)


