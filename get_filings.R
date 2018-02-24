library(dplyr, warn.conflicts = FALSE)

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

# Add data for years 1993 to 2017 ----
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

for (year in 1993:2017) {
    for (quarter in 1:4) {
        deleteIndexDataFomDatabase(pg, year, quarter)
        addIndexFileToDatabase(getSECIndexFile(year, quarter))
    }
}
rs <- dbDisconnect(pg)

# Add data for 2018 ----
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

for (year in 2018) {
    for (quarter in 1) {
        deleteIndexDataFomDatabase(pg, year, quarter)
        addIndexFileToDatabase(getSECIndexFile(year, quarter))
    }
}
rs <- dbDisconnect(pg)
