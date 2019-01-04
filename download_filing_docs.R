library(RPostgreSQL)
library(dplyr, warn.conflicts = FALSE)
library(tools)

# Functions ----
get_file_list <- function(num_files = Inf, form_types = NULL) {

    pg <- dbConnect(PostgreSQL())

    filings <- tbl(pg, sql("SELECT * FROM edgar.filings"))
    filing_docs  <- tbl(pg, sql("SELECT * FROM edgar.filing_docs"))
    filing_docs_processed <- tbl(pg, sql("SELECT * FROM edgar.filing_docs_processed"))

    if (is.null(form_types)) {
        filing_docs_to_get <- filing_docs
    } else {
        filing_docs_to_get <-
            filings %>%
            filter(form_type %in% form_types) %>%
            inner_join(filing_docs)
    }

    get_file_path <- function(file_name, document) {
        url <- gsub("(\\d{10})-(\\d{2})-(\\d{6})\\.txt", "\\1\\2\\3", file_name)
        file.path(url, document)
    }

    new_table <- !dbExistsTable(pg, c("edgar", "filing_docs_processed"))
    if (!new_table) {
        files <-
            filing_docs_to_get  %>%
            anti_join(filing_docs_processed)
    } else {
        files <- filing_docs_to_get
    }

    files <-
        files %>%
        filter(document %~*% "htm$") %>%
        collect(n = num_files) %>%
        mutate(html_link = get_file_path(file_name, document))

    dbDisconnect(pg)

    return(files)
}

get_filing_file_list <- function(file_name, num_files = Inf) {

    pg <- dbConnect(PostgreSQL())

    filing_docs  <- tbl(pg, sql(paste0("SELECT * FROM edgar.filing_docs WHERE file_name = '", file_name, "'")))
    filing_docs_processed <- tbl(pg, sql(paste0("SELECT * FROM edgar.filing_docs_processed WHERE file_name = '", file_name, "'")))

    get_file_path <- function(file_name, document) {
        url <- gsub("(\\d{10})-(\\d{2})-(\\d{6})\\.txt", "\\1\\2\\3", file_name)
        file.path(url, document)
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
        filter(document %~*% "htm$") %>%
        collect(n = num_files) %>%
        mutate(html_link = get_file_path(file_name, document))

    dbDisconnect(pg)

    return(files)
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



download_filing_files <- function(file_name, max_files = Inf) {


    pg <- dbConnect(PostgreSQL())
    new_table <- !dbExistsTable(pg, c("edgar", "filing_docs_processed"))
    dbDisconnect(pg)
    while (nrow(files <- get_filing_file_list(file_name, num_files = max_files))>0) {
        print("Getting files...")
        st <- system.time(files$downloaded <-
                              unlist(lapply(files$html_link, get_filing_docs)))

        print(sprintf("Downloaded %d files in %3.2f seconds",
                      nrow(files), st[["elapsed"]]))

        downloaded_files <-
            files %>%
            select(file_name, document, downloaded)

        pg <- dbConnect(PostgreSQL())
        dbWriteTable(pg, c("edgar", "filing_docs_processed"), downloaded_files,
                     append = !new_table,
                     row.names = FALSE)
        if (new_table) {
            dbGetQuery(pg, "CREATE INDEX ON edgar.filing_docs_processed (file_name)")
            dbGetQuery(pg, "ALTER TABLE edgar.filing_docs_processed OWNER TO edgar")
            dbGetQuery(pg, "GRANT SELECT ON TABLE edgar.filing_docs_processed TO edgar_access")
            new_table <- FALSE
        }
        dbDisconnect(pg)




}

}

# Run code ----
library(parallel)

raw_directory <- Sys.getenv("EDGAR_DIR")

new_table <- !dbExistsTable(pg, c("edgar", "filing_docs_processed"))
while (nrow(files <- get_file_list(num_files = Inf, form_types = "8-K"))>0) {
    print("Getting files...")
    st <- system.time(files$downloaded <-
                    unlist(mclapply(files$html_link, get_filing_docs,
                                mc.cores=24)))

    print(sprintf("Downloaded %d files in %3.2f seconds",
                  nrow(files), st[["elapsed"]]))

    downloaded_files <-
        files %>%
        select(file_name, document, downloaded)

    pg <- dbConnect(PostgreSQL())
    dbWriteTable(pg, c("edgar", "filing_docs_processed"), downloaded_files,
             append = !new_table,
             row.names = FALSE)
    if (new_table) {
        dbGetQuery(pg, "CREATE INDEX ON edgar.filing_docs_processed (file_name)")
        dbGetQuery(pg, "ALTER TABLE edgar.filing_docs_processed OWNER TO edgar")
        dbGetQuery(pg, "GRANT SELECT ON TABLE edgar.filing_docs_processed TO edgar_access")
        new_table <- FALSE
    }
    dbDisconnect(pg)
}
get_file_list
