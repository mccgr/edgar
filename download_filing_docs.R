
Sys.setenv(EDGAR_DIR="shared")
raw_directory <- Sys.getenv("EDGAR_DIR")

library(RPostgreSQL)
library(dplyr)
library(stringr)

pg <- dbConnect(PostgreSQL())

filing_docs  <- tbl(pg, sql("SELECT * FROM edgar.filing_docs"))
filing_docs_processed <- tbl(pg, sql("SELECT * FROM edgar.filing_docs_processed"))

get_file_path <- function(file_name, document) {
    url <- gsub("(\\d{10})-(\\d{2})-(\\d{6})\\.txt", "\\1\\2\\3", file_name)
    file.path(url, document)
}

get_file_type<-function(document){
    str_sub(document,-3,-1)
}

new_table <- !dbExistsTable(pg, c("edgar", "filing_docs_processed"))
if (!new_table) {
    files <-
        filing_docs  %>%
        anti_join(filing_docs_processed)
} else {
    files <- filing_docs
}

files <-
    files %>%
    collect(n=140) %>%
    mutate(html_link = get_file_path(file_name, document))

get_filing_docs <- function(path) {

    local_filename <- file.path(raw_directory, path)

    #     print(path[!file.exists(local_filename) & !is.na(path)])
    link <- file.path("https://www.sec.gov/Archives", path)
    dir.create(dirname(local_filename), showWarnings=FALSE, recursive=TRUE)

    # Only download the file if we don't already have a local copy
    if (!file.exists(local_filename)) {
        try(download.file(url=link, destfile=local_filename, quiet=TRUE))
    }

    # Return the local filename if the file exists
    return(file.exists(local_filename))
}

library(parallel)
files$downloaded <- unlist(mclapply(files$html_link, get_filing_docs, mc.cores=6))

downloaded_files <-
    files %>%
    select(file_name, document, downloaded)

dbWriteTable(pg, c("edgar", "filing_docs_processed"), downloaded_files,
             append = !new_table,
             row.names = FALSE)

dbDisconnect(pg)
