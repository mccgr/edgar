# Create functions to get filings ----
library(dplyr, warn.conflicts = FALSE)

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

    rs <- dbGetQuery(pg, "CREATE SCHEMA IF NOT EXISTS edgar")

    rs <- dbWriteTable(pg, c("edgar", "filings"), data,
                                         append=TRUE, row.names=FALSE)

    rs <- dbGetQuery(pg, "ALTER TABLE edgar.filings OWNER TO edgar")
    rs <- dbGetQuery(pg, "GRANT SELECT ON TABLE edgar.filings TO edgar_access")

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

# find the last quarter and year from the current database ----

library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

filings <- tbl(pg, sql("SELECT * FROM edgar.filings"))

last_quarter <-
    filings %>%
    mutate(year = date_part('year', date_filed),
           quarter = date_part('quarter', date_filed)) %>%
    filter(year == max(year, na.rm = TRUE)) %>%
    summarise(year = max(year, na.rm = TRUE),
              quarter = max(quarter, na.rm = TRUE)) %>%
    collect()

rs <- dbDisconnect(pg)

# Add data for years 1993 to the last year and quarter of the current database ----

library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

for (year in 1993:(last_quarter$year-1)) {
    for (quarter in 1:4) {
        deleteIndexDataFomDatabase(pg, year, quarter)
        addIndexFileToDatabase(getSECIndexFile(year, quarter))
    }
}

for (quarter in 1:last_quarter$quarter) {
    deleteIndexDataFomDatabase(pg, last_quarter$year, quarter)
    addIndexFileToDatabase(getSECIndexFile(last_quarter$year, quarter))
}

rs <- dbDisconnect(pg)


# Find the current year and quarter ----

library(lubridate)

current_year <- year(today())
current_quarter <- quarter(today())



# Add data up to current year and quarter ----

library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

if(current_year == last_quarter$year) {

# If current_year is equal to last_quarter$year, and the current quarter is later than that of the last update to the
# database, add data from the quarter after the last update up to and including the current quarter


    if(current_quarter > last_quarter$quarter) {

        for(quarter in (last_quarter$quarter + 1):current_quarter) {

            deleteIndexDataFomDatabase(pg, current_year, quarter)
            addIndexFileToDatabase(getSECIndexFile(current_year, quarter))

        }

    }

} else if(current_year == last_quarter$year + 1) {

# If the current year is the year after the year of the last update, add data for the remaining quarters of
# last_quarter$year ...

    for(quarter in (last_quarter$quarter + 1):4) {

        deleteIndexDataFomDatabase(pg, last_quarter$year, quarter)
        addIndexFileToDatabase(getSECIndexFile(last_quarter$year, quarter))

    }

# then data for the quarters of the current year, up to and including the current quarter

    for (quarter in 1:current_quarter) {
        deleteIndexDataFomDatabase(pg, current_year, quarter)
        addIndexFileToDatabase(getSECIndexFile(current_year, quarter))
    }


} else if(current_year > last_quarter$year + 1) {

# finally, if current_year is at least 2 years greater than last_quarter$year, do same as the previous case, but add data
# for all 4 quarters for each year in between last_quarter$year and current_year (middle for loop)

    for(quarter in (last_quarter$quarter + 1):4) {

        deleteIndexDataFomDatabase(pg, last_quarter$year, quarter)
        addIndexFileToDatabase(getSECIndexFile(last_quarter$year, quarter))

    }

    for(year in (last_quarter$year + 1):(current_year - 1)) {
            for (quarter in 1:4) {
                deleteIndexDataFomDatabase(pg, year, quarter)
                addIndexFileToDatabase(getSECIndexFile(year, quarter))
        }
    }

    for (quarter in 1:current_quarter) {
        deleteIndexDataFomDatabase(pg, current_year, quarter)
        addIndexFileToDatabase(getSECIndexFile(current_year, quarter))
    }

}

rs <- dbDisconnect(pg)
