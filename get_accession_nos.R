library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)

pg <- dbConnect(PostgreSQL())

rs <- dbExecute(pg, "SET work_mem='10GB'")
rs <- dbExecute(pg, "SET search_path TO edgar")

filings <- tbl(pg, "filings")

acc_no_regex <- "edgar/data/\\d+/(.*)\\.txt$"

if (dbExistsTable(pg, "accession_numbers")) {
    accession_numbers <- tbl(pg, "accession_numbers")

    new_filings <-
        filings %>%
        anti_join(accession_numbers) %>%
        select(file_name) %>%
        compute()

    acc_nos_new <-
        new_filings %>%
        mutate(accessionnumber =
                   regexp_replace(file_name, acc_no_regex, "\\1")) %>%
        select(file_name, accessionnumber) %>%
        compute(name="acc_number_temp",
                indexes = c("accessionnumber", "file_name"))

    dbGetQuery(pg, "INSERT INTO accession_numbers SELECT * FROM acc_number_temp")

    dbGetQuery(pg, "DROP TABLE IF EXISTS acc_number_temp")
} else {
    acc_nos_all <-
        filings %>%
            mutate(accessionnumber = regexp_replace(file_name,
                                                    acc_no_regex, "\\1")) %>%
            select(file_name, accessionnumber) %>%
            compute(name = "accession_numbers",
                    indexes = c("accessionnumber", "file_name"),
                    temporary = FALSE)

    dbGetQuery(pg, "ALTER TABLE accession_numbers OWNER TO edgar")
    dbGetQuery(pg, "GRANT SELECT ON accession_numbers TO edgar_access")
}

dbDisconnect(pg)
