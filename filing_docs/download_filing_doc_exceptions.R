library(DBI)
library(dplyr, warn.conflicts = FALSE)
library(tools)
source('filing_docs/scrape_filing_doc_functions.R')
source('filing_docs/download_filing_docs_functions.R')


# Functions ----


get_filing_doc_exception_list <- function(num_files = Inf) {

    pg <- dbConnect(RPostgreSQL::PostgreSQL())

    new_table <- !dbExistsTable(pg, c("edgar", "filing_docs_processed"))
    if (new_table) {

        return(data.frame(matrix(nrow = 0, ncol = 0)))

    } else {

        failed_to_download <- tbl(pg, sql("SELECT * FROM edgar.filing_docs_processed WHERE NOT downloaded"))

        table_alt_exists <- dbExistsTable(pg, c("edgar", "filing_docs_alt"))

        if(table_alt_exists) {

            filing_docs_alt <- tbl(pg, sql("SELECT * FROM edgar.filing_docs_alt"))

            files <-
                failed_to_download %>%
                anti_join(filing_docs_alt, by = c("file_name", "document")) %>%
                filter(document %~*% "txt$") %>%
                collect(n = num_files)

        } else {

            files <-
                failed_to_download %>%
                filter(document %~*% "txt$") %>%
                collect(n = num_files)

        }

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


filing_docs_df_with_href <- function(file_name) {


    try({head_url <- get_index_url(file_name)

    table_nodes <-
        read_html(head_url, encoding="Latin1") %>%
        html_nodes("table")

    if (length(table_nodes) < 1) {
        df <- tibble(seq = NA, description = NA, document = NA, type = NA,
                     size = NA, file_name = file_name)
    } else {

        df <- table_nodes %>% html_table() %>% bind_rows() %>% fix_names() %>% mutate(file_name = file_name, type = as.character(type))

        colnames(df) <- tolower(colnames(df))

        hrefs <- table_nodes %>% html_nodes("tr") %>% html_nodes("a") %>% html_attr("href")

        hrefs <- unlist(lapply(hrefs, function(x) {gsub('/Archives/', '', x)}))

        df$path_alt <- hrefs

    }


    return(df)}, {return(tibble(seq = NA, description = NA, document = NA, type = NA, size = NA, file_name = file_name))})

}

get_filing_docs_alt <- function(file_name) {


    try({head_url <- get_index_url(file_name)

    table_nodes <-
        read_html(head_url, encoding="Latin1") %>%
        html_nodes("table")

    if (length(table_nodes) < 1) {
        df <- tibble(seq = NA, description = NA, document = NA, type = NA,
                     size = NA, file_name = file_name)
    } else {

        df <- table_nodes %>% html_table() %>% bind_rows() %>% fix_names() %>% mutate(file_name = file_name, type = as.character(type))

        colnames(df) <- tolower(colnames(df))

        hrefs <- table_nodes %>% html_nodes("tr") %>% html_nodes("a") %>% html_attr("href")

        hrefs <- unlist(lapply(hrefs, function(x) {paste0('https://www.sec.gov', x)}))

        df$html_link <- hrefs
    }

    pg <- dbConnect(PostgreSQL())
    dbWriteTable(pg, c("edgar", "filing_docs_alt"),
                 df, append = TRUE, row.names = FALSE)
    dbDisconnect(pg)

    return(TRUE)}, {return(FALSE)})


}

download_exceptional_filing_document <- function(file_name, document, path_alt=NA) {

    if (is.na(path_alt)) {

        path <- get_file_path(file_name, document)

    } else {

        path <- path_alt

    }

    local_filename <- file.path(raw_directory, path)

    #     print(path[!file.exists(local_filename) & !is.na(path)])
    html_link <- file.path("https://www.sec.gov/Archives", path)
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
    new_table <- !dbExistsTable(pg, c("edgar", "filing_docs_alt"))
    dbDisconnect(pg)
    while (nrow(files <- get_filing_doc_exception_list(num_files = max_files))>0) {
        print("Getting files...")
        st <- system.time(files$downloaded <-
                              unlist(lapply(1:nrow(files), function(j) {download_exceptional_filing_document(files$file_name[j], files$document[j], files$path_alt[j])})))

        print(sprintf("Downloaded %d files in %3.2f seconds",
                      nrow(files), st[["elapsed"]]))

        pg <- dbConnect(PostgreSQL())

        dbWriteTable(pg, c("edgar", "filing_docs_alt"), files, append = !new_table, row.names = FALSE)

        if (new_table) {
            dbGetQuery(pg, "CREATE INDEX ON edgar.filing_docs_alt (file_name)")
            dbGetQuery(pg, "ALTER TABLE edgar.filing_docs_alt OWNER TO edgar")
            dbGetQuery(pg, "GRANT SELECT ON TABLE edgar.filing_docs_alt TO edgar_access")
            new_table <- FALSE
        }

        dbDisconnect(pg)
    }


}

# Run code ----
library(parallel)

raw_directory <- Sys.getenv("EDGAR_DIR")

download_exceptional_filing_document_list(max_files = 100)

