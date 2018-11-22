#!/usr/bin/env Rscript
library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL, quietly = TRUE)
library(rvest, quietly = TRUE)
library(parallel)

get_index_url <- function(file_name) {
    matches <- stringr::str_match(file_name, "/(\\d+)/(\\d{10}-\\d{2}-\\d{6})")
    cik <- matches[2]
    acc_no <- matches[3]
    path <- stringr::str_replace_all(acc_no, "[^\\d]", "")

    url <- paste0("https://www.sec.gov/Archives/edgar/data/", cik, "/", path, "/",
                  acc_no, "-index.htm")
    return(url)
}

get_filing_docs <- function(file_name) {


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
    }

    pg <- dbConnect(PostgreSQL())
    dbWriteTable(pg, c("edgar", "filing_docs"),
                 df, append = TRUE, row.names = FALSE)
    dbDisconnect(pg)

    return(TRUE)}, {return(FALSE)})


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
# A function which takes as an argument a regular expression which catches filings of one or several types, and returns the file names for the set of filings from edgar.filings filtered by those types for which
# the documents have not yet been processed into edgar.filing_docs

    pg <- dbConnect(PostgreSQL())

    filings <- tbl(pg, sql("SELECT * FROM edgar.filings"))

    type_filings <-
        filings %>%
        filter(form_type %~% type_regex)

    new_table <- !dbExistsTable(pg, c("edgar", "filing_docs"))

    if (!new_table) {
        filing_docs <- tbl(pg, sql("SELECT * FROM edgar.filing_docs"))
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

    pg <- dbConnect(PostgreSQL())
    new_table <- !dbExistsTable(pg, c("edgar", "filing_docs"))

    system.time(temp <- mclapply(filings_df$file_name, get_filing_docs, mc.cores = 24))

    if (new_table) {
        rs <- dbExecute(pg, "CREATE INDEX ON edgar.filing_docs (file_name)")
        rs <- dbExecute(pg, "ALTER TABLE edgar.filing_docs OWNER TO edgar")
        rs <- dbExecute(pg, "GRANT SELECT ON TABLE edgar.filing_docs TO edgar_access")
    }

    rs <- dbDisconnect(pg)
    temp <- unlist(temp)

    return(temp)

}

process_filings_alt <- function(filings_df) {

    pg <- dbConnect(PostgreSQL())
    new_table <- !dbExistsTable(pg, c("edgar", "filing_docs_alt"))

    system.time(temp <- mclapply(filings_df$file_name,
                                 get_filing_docs_alt, mc.cores = 24))

    if (new_table) {
        rs <- dbExecute(pg, "CREATE INDEX ON edgar.filing_docs_alt (file_name)")
        rs <- dbExecute(pg, "ALTER TABLE edgar.filing_docs_alt OWNER TO edgar")
        rs <- dbExecute(pg, "GRANT SELECT ON TABLE edgar.filing_docs_alt TO edgar_access")
    }

    rs <- dbDisconnect(pg)

    temp <- unlist(temp)

    return(temp)

}

