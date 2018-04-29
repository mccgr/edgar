#!/usr/bin/env Rscript
library(xml2)
library(stringr)
library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL, quietly = TRUE)
library(parallel)

regex <- "edgar/data/(\\d+)/(\\d{10})-(\\d{2})-(\\d{6}).txt"

get_sgml_url <- function(file_name) {
    matches <- str_match(file_name, regex)
    url <- paste0("https://www.sec.gov/Archives/edgar/data/",
                  matches[2], "/",
                  paste0(matches[3:5], collapse=""), "/",
                  matches[3], "-", matches[4], "-", matches[5],
                  ".hdr.sgml")
    return(url)
}

get_filed_by_cik <- function(file_name) {

    res <- NA

    try({
        url <- get_sgml_url(file_name)
        temp <- as_xml_document(read_html(url))
        filed_by <- xml_find_first(temp, ".//filed-by")
        res <- str_extract(xml_find_first(filed_by, ".//cik"), "(?<=<cik>)(\\d+)")
        res <- as.integer(res)
    })

    return(res)
}

pg <- dbConnect(PostgreSQL())
rs <- dbExecute(pg, "SET search_path TO edgar")

if (!dbExistsTable(pg, "filer_ciks")) {
    rs <- dbExecute(pg, "
        CREATE TABLE filer_ciks (file_name text, filer_cik integer);
        CREATE INDEX ON filer_ciks (file_name);
        ALTER TABLE filer_ciks OWNER TO edgar;
        GRANT SELECT ON filer_ciks TO edgar_access;")
}

filings <- tbl(pg, "filings")
filer_ciks <- tbl(pg, "filer_ciks")

get_file_names <- function() {
    temp <-
        filings %>%
        filter(form_type %in% c("SC 13D", "SC 13G")) %>%
        anti_join(filer_ciks, by = "file_name") %>%
        select(file_name) %>%
        collect(n = 200) %>%
        distinct()
    if (nrow(temp) > 0) pull(temp)
}

while(length(file_name <- get_file_names()) > 0) {

    filer_cik <- unlist(mclapply(file_name, get_filed_by_cik, mc.cores = 10))

    rs <- dbWriteTable(pg, name = "filer_ciks", tibble(file_name, filer_cik),
                 append = TRUE, row.names = FALSE)
}

rs <- dbDisconnect(pg)
