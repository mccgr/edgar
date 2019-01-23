library(DBI)
library(dplyr, warn.conflicts = FALSE)
library(tools)
source('download_filing_docs_functions.R')

# Functions ----


get_filing_doc_exception_list <- function(num_files = Inf) {

    pg <- dbConnect(RPostgreSQL::PostgreSQL())

    new_table <- !dbExistsTable(pg, c("edgar", "filing_docs_processed"))
    if (new_table) {

        return(data.frame(matrix(nrow = 0, ncol = 0)))

    } else {

        failed_to_download <- tbl(pg, sql("SELECT * FROM edgar.filing_docs_processed WHERE NOT downloaded"))

        files <-
            failed_to_download %>%
            filter(document %~*% "htm$") %>%
            collect(n = num_files)

        unique_file_names <- unique(files$file_name)

        filing_docs_with_htmls <- bind_rows(lapply(unique_file_names, filing_docs_df_with_href))

        files <- files %>% inner_join(filing_docs_with_htmls, by = c("file_name", "document"))

        dbDisconnect(pg)

        return(files)

    }


}

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

download_exceptional_filing_document <- function(file_name, document, html_link) {

    path <- get_file_path(file_name, document)

    local_filename <- file.path(raw_directory, path)

    #     print(path[!file.exists(local_filename) & !is.na(path)])
    link <- file.path("https://www.sec.gov/Archives", path)
    dir.create(dirname(local_filename), showWarnings=FALSE, recursive=TRUE)

    # Only download the file if we don't already have a local copy
    if (!file.exists(local_filename)) {
        try(download.file(url=html_link, destfile=local_filename, quiet=TRUE))
    }

    # Return the local filename if the file exists
    return(file.exists(local_filename))


}


download_exceptional_filing_document_list <- function(max_files = Inf) {

    pg <- dbConnect(RPostgreSQL::PostgreSQL())
    new_table <- !dbExistsTable(pg, c("edgar", "filing_docs_alt_html"))
    dbDisconnect(pg)
    while (nrow(files <- get_filing_doc_exception_list(num_files = max_files))>0) {
        print("Getting files...")
        st <- system.time(files$downloaded <-
                              unlist(lapply(1:nrow(files), function(j) {download_exceptional_filing_document(files$file_name[j], files$document[j], files$html_link[j])})))

        print(sprintf("Downloaded %d files in %3.2f seconds",
                      nrow(files), st[["elapsed"]]))

        update_filing_docs_processed <- function(file_name, document, downloaded) {

            dbExecute(pg, paste0("UPDATE edgar.filing_docs_processed SET downloaded = ", downloaded, " WHERE file_name = '", file_name, "' AND document = '", document, "'"))

        }


        pg <- dbConnect(PostgreSQL())

        lapply(1:nrow(files), function(j) {update_filing_docs_processed(files$file_name[j], files$document[j], files$downloaded[j])})

        successes <- files %>% filter(downloaded == TRUE) %>% select(file_name, document, html_link)

        dbWriteTable(pg, c("edgar", "filing_docs_alt"), successes, append = !new_table, row.names = FALSE)

        if (new_table) {
            dbGetQuery(pg, "CREATE INDEX ON edgar.filing_docs_alt_html (file_name)")
            dbGetQuery(pg, "ALTER TABLE edgar.filing_docs_alt_html OWNER TO edgar")
            dbGetQuery(pg, "GRANT SELECT ON TABLE edgar.filing_docs_alt_html TO edgar_access")
            new_table <- FALSE
        }

        dbDisconnect(pg)
    }


}

# Run code ----
library(parallel)

raw_directory <- Sys.getenv("EDGAR_DIR")

download_exceptional_filing_document_list()

