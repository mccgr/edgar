library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL)

pg <- dbConnect(PostgreSQL())

dbGetQuery(pg, "SET work_mem='10GB'")
filings <- tbl(pg, sql("SELECT * FROM edgar.filings"))

acc_no_regex <- "edgar/data/\\d+/(.*)\\.txt$"

if (dbExistsTable(pg, c("edgar", "accession_numbers"))) {
    accession_numbers <- tbl(pg, sql("SELECT * FROM edgar.accession_numbers"))

    new_filings <-
        filings %>%
        anti_join(accession_numbers) %>%
        select(file_name) %>%
        compute()

    acc_nos_new <-
        new_filings %>%
        mutate(accessionnumber = regexp_replace(file_name, acc_no_regex, "\\1")) %>%
        select(file_name, accessionnumber) %>%
        compute(name="accession_numbers", indexes = c("accessionnumber", "file_name"))

    dbGetQuery(pg, "INSERT INTO edgar.accession_numbers SELECT * FROM accession_numbers")

    dbGetQuery(pg, "DROP TABLE IF EXISTS accession_numbers")
} else {
    acc_nos_all <-
        filings %>%
            mutate(accessionnumber = regexp_replace(file_name, acc_no_regex, "\\1")) %>%
            select(file_name, accessionnumber) %>%
            compute(name="accession_numbers",
                    indexes = c("accessionnumber", "file_name"),
                    temporary = FALSE)

    dbGetQuery(pg, "ALTER TABLE accession_numbers SET SCHEMA edgar")

    dbGetQuery(pg, "ALTER TABLE edgar.accession_numbers OWNER TO edgar")
    # dbGetQuery(pg, "CREATE ROLE edgar_access")
    dbGetQuery(pg, "GRANT SELECT ON edgar.accession_numbers TO edgar_access")
}

dbDisconnect(pg)
