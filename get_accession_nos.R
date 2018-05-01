#!/usr/bin/env Rscript
library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL, quietly = TRUE)

pg <- dbConnect(PostgreSQL())

rs <- dbExecute(pg, "SET work_mem='10GB'")
rs <- dbExecute(pg, "SET search_path TO edgar")

filings <- tbl(pg, "filings")

acc_no_regex <- "edgar/data/\\d+/(.*)\\.txt$"

if (dbExistsTable(pg, "accession_numbers")) {
    accession_numbers <- tbl(pg, "accession_numbers")

    new_filings <-
        filings %>%
        anti_join(accession_numbers, by = "file_name") %>%
        select(file_name) %>%
        compute()

    acc_nos_new <-
        new_filings %>%
        mutate(accessionnumber =
                   regexp_replace(file_name, acc_no_regex, "\\1")) %>%
        select(file_name, accessionnumber) %>%
        compute(name="acc_number_temp",
                indexes = c("accessionnumber", "file_name"))

    rs <- dbExecute(pg, "INSERT INTO accession_numbers SELECT * FROM acc_number_temp")

    rs <- dbExecute(pg, "DROP TABLE IF EXISTS acc_number_temp")
} else {
    acc_nos_all <-
        filings %>%
            mutate(accessionnumber = regexp_replace(file_name,
                                                    acc_no_regex, "\\1")) %>%
            select(file_name, accessionnumber) %>%
            compute(name = "accession_numbers",
                    indexes = c("accessionnumber", "file_name"),
                    temporary = FALSE)

    rs <- dbExecute(pg, "ALTER TABLE accession_numbers OWNER TO edgar")
    rs <- dbExecute(pg, "GRANT SELECT ON accession_numbers TO edgar_access")
}

rs <- dbDisconnect(pg)
