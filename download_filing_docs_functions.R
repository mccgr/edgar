raw_directory <- Sys.getenv("EDGAR_DIR")

library(RPostgreSQL)
library(dplyr)
library(tools)

get_file_path <- function(file_name, document) {
    url <- gsub("(\\d{10})-(\\d{2})-(\\d{6})\\.txt", "\\1\\2\\3", file_name)
    file.path(url, document)
}

get_file_list <- function(num_files = Inf) {

    pg <- dbConnect(PostgreSQL())

    rs <- dbExecute(pg, "SET search_path TO edgar")

    filing_docs  <- tbl(pg, "filing_docs")
    filing_docs_processed <- tbl(pg, "filing_docs_processed")

    new_table <- !dbExistsTable(pg, "filing_docs_processed")
    if (!new_table) {
        files <-
            filing_docs  %>%
            anti_join(filing_docs_processed)
    } else {
        files <- filing_docs
    }

    files <-
        files %>%
        collect(n = num_files) %>%
        mutate(html_link = get_file_path(file_name, document))

    dbDisconnect(pg)

    return(files)
}

get_filing_docs <- function(path) {

    local_filename <- file.path(raw_directory, path)

    link <- file.path("https://www.sec.gov/Archives", path)
    dir.create(dirname(local_filename), showWarnings=FALSE, recursive=TRUE)

    # Only download the file if we don't already have a local copy
    if (!file.exists(local_filename)) {
        try(download.file(url=link, destfile=local_filename, quiet=TRUE))
    }

    # Return the local filename if the file exists
    return(file.exists(local_filename))
}

browse_filing_doc <- function(path) {

    local_filename <- file.path(raw_directory, path)

    browseURL(local_filename)
}
