#!/usr/bin/env Rscript
library(parallel)
library(rvest)
library(dplyr, warn.conflicts = FALSE)
library(tidyr, warn.conflicts = FALSE)

# Functions ----
get_index_url <- function(file_name) {
    matches <- stringr::str_match(file_name, "/(\\d+)/(\\d{10}-\\d{2}-\\d{6})")
    cik <- matches[2]
    acc_no <- matches[3]
    path <- stringr::str_replace_all(acc_no, "[^\\d]", "")

    url <- paste0("https://www.sec.gov/Archives/edgar/data/", cik, "/", path, "/",
                  acc_no, "-index.htm")
    return(url)
}

html_table_mod <- function(table) {
    lapply(html_table(table), function(x) mutate(x, Type = as.character(Type)))
}

fix_names <- function(df) {
    colnames(df) <- tolower(colnames(df))
    df
}

get_filing_doc_url <- function(file_name, document) {

    url <- paste('https://www.sec.gov/Archives',
                 gsub("(\\d{10})-(\\d{2})-(\\d{6})\\.txt", "\\1\\2\\3", file_name), document, sep = '/')

    return(url)

}

filing_docs_df <- function(file_name) {
    head_url <- get_index_url(file_name)

    table_nodes <-
        try({
            read_html(head_url, encoding="Latin1") %>%
                html_nodes("table")
        })

    if (length(table_nodes) < 1 | is(table_nodes, "try-error")) {
        df <- tibble(seq = NA, description = NA, document = NA, type = NA,
                     size = NA, file_name = file_name)
        return(df)
    } else {
        filing_doc_table_indices <-
            which(table_nodes %>% html_attr("class") == "tableFile")

        file_tables <- table_nodes[filing_doc_table_indices]
        df <-
            file_tables %>%
            html_table_mod() %>%
            bind_rows() %>%
            fix_names() %>%
            mutate(file_name = file_name,
                   type = as.character(type),
                   description = as.character(description)) %>%
            separate(col = document,
                     into = c("document", "document_note"),
                     sep = "[[:space:]]+")


        df$url <- file_tables %>%
            html_nodes(xpath = 'tr/td/a[@href]') %>%
            html_attr('href') %>%
            stringr::str_replace('^.*(/ix?doc=)?/Archives/', '')

        url_full <- paste0('https://www.sec.gov/Archives/', df$url)

        norm_url <- get_filing_doc_url(df$file_name, df$document)

        df$url[url_full == norm_url] <- NA

        colnames(df) <- tolower(colnames(df))
    }

    return(df)
}


get_filing_docs <- function(file_name) {

    try({
        df <- filing_docs_df(file_name)
        pg <- dbConnect(RPostgres::Postgres())
        dbWriteTable(pg, c(target_schema, target_table),
                     df, append = TRUE, row.names = FALSE)
        dbDisconnect(pg)

        return(TRUE)
    }, { return(FALSE) })

}

fix_names <- function(df) {
    colnames(df) <- tolower(colnames(df))
    return(df)
}

get_filing_docs_table_nodes <- function(file_name) {

    head_url <- get_index_url(file_name)

    table_nodes <-
        read_html(head_url, encoding="Latin1") %>%
        html_nodes("table")

    return(table_nodes)
}

get_num_tables <- function(file_name) {

    table_nodes <- get_filing_docs_table_nodes(file_name)
    num_tables <- length(table_nodes)
    return(num_tables)
}

get_filings_by_type <- function(type_regex) {
    # A function which takes as an argument a regular expression which
    # catches filings of one or several types, and returns the file names
    # for the set of filings from edgar.filings filtered by those types for which
    # the documents have not yet been processed into edgar.filing_docs

    pg <- dbConnect(RPostgres::Postgres())

    filings <- tbl(pg, sql("SELECT * FROM edgar.filings"))

    type_filings <-
        filings %>%
        filter(form_type %~% type_regex)

    new_table <- !dbExistsTable(pg, c(target_schema, target_table))

    if (!new_table) {
        filing_docs <- tbl(pg, sql(paste0("SELECT * FROM ", target_schema, ".", target_table)))
        type_filings <- type_filings %>% anti_join(filing_docs, by = "file_name")
    }

    file_names <-
        type_filings %>%
        select(file_name) %>%
        distinct() %>%
        collect()
    rs <- dbDisconnect(pg)

    return(file_names)
}

process_filings <- function(filings_df) {

    pg <- dbConnect(RPostgres::Postgres())
    new_table <- !dbExistsTable(pg, c(target_schema, target_table))

    system.time(temp <- mclapply(filings_df$file_name, get_filing_docs, mc.cores = 24))

    if (new_table) {
        rs <- dbExecute(pg, paste0("SET search_path TO ", target_schema))
        rs <- dbExecute(pg, paste0("CREATE INDEX ON ", target_table, " (file_name)"))
        rs <- dbExecute(pg, paste0("ALTER TABLE ", target_table,
                                   " OWNER TO edgar"))
        rs <- dbExecute(pg, paste0("GRANT SELECT ON TABLE ", target_table,
                                   " TO edgar_access"))
    }

    rs <- dbDisconnect(pg)
    temp <- unlist(temp)

    return(temp)
}
