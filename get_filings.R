# Create functions to get filings ----
getSECIndexFile <- function(year, quarter) {

    library(curl)
    # Download the zipped index file from the SEC website
    tf <- tempfile()
    result <- try(curl_download(
        url=paste("http://www.sec.gov/Archives/edgar/full-index/",
                            year,"/QTR", quarter, "/company.zip",sep=""),
        destfile=tf))

    # If we didn't encounter and error downloading the file, parse it
    # and return as a R data frame
    if (!inherits(result, "try-error")) {

        # Small function to remove leading and trailing spaces
        trim <- function (string) {
            Encoding(string) <- "latin1"
            string <- enc2native(string)
            gsub("^\\s*(.*?)\\s*$","\\1", string, perl=TRUE)
        }

        # Read the downloaded file
        raw.data <- readLines(con=(zz<- unz(description=tf,
                                            filename="company.idx")))
        close(zz)
        raw.data <- raw.data[11:length(raw.data)] # Remove the first 10 rows.

        # Parse the downloaded file and return the extracted data as a data frame
        company_name <- trim(substr(raw.data,1,62))
        form_type <- trim(substr(raw.data,63,74))
        cik <- trim(substr(raw.data,75,86))
        date_filed <- as.Date(substr(raw.data,87,98))
        file_name <- trim(substr(raw.data,99,150))
        rm(raw.data)
        return(data.frame(company_name, form_type, cik, date_filed, file_name))
    } else { return(NULL)}
}

addIndexFileToDatabase <- function(data) {
    if (is.null(data)) return(NULL)
    library(RPostgreSQL)
    pg <- dbConnect(PostgreSQL())

    rs <- dbGetQuery(pg, "CREATE SCHEMA IF NOT EXISTS edgar")

    rs <- dbWriteTable(pg, c("edgar", "filings"), data,
                                         append=TRUE, row.names=FALSE)
    dbDisconnect(pg)
    return(rs)
}

# Add data for years 1993 to 2016 ----
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())
# dbGetQuery(pg, "DROP TABLE IF EXISTS edgar.filings")

for (year in 1993:2016) {
    for (quarter in 1:4) {
        if(dbExistsTable(pg, c("edgar", "filings"))) {
           dbGetQuery(pg, paste(
            "DELETE
             FROM edgar.filings
             WHERE extract(quarter FROM date_filed)=", quarter,
           " AND extract(year FROM date_filed)=", year))
        }
    addIndexFileToDatabase(getSECIndexFile(year, quarter))
    }
}
rs <- dbDisconnect(pg)

# Add data for 2017 ----
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

for (year in 2017) {
    for (quarter in 1:2) {
        if(dbExistsTable(pg, c("edgar", "filings"))) {
            dbGetQuery(pg, paste(
                "DELETE
             FROM edgar.filings
             WHERE extract(quarter FROM date_filed)=", quarter,
                " AND extract(year FROM date_filed)=", year))
        }
        addIndexFileToDatabase(getSECIndexFile(year, quarter))
    }
}
rs <- dbDisconnect(pg)
