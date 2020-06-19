library(dplyr, warn.conflicts = FALSE)
library(DBI)

pg <- dbConnect(RPostgres::Postgres())
rs <- dbExecute(pg, "SET search_path TO edgar")

cusip_cik <- tbl(pg, "cusip_cik")

# These are the valid 9-digit CUSIPs (based on check digit)
valid_cusip9s <-
    cusip_cik %>%
    filter(nchar(cusip) == 9) %>%
    filter(substr(cusip, 9, 9) == as.character(check_digit)) %>%
    compute()

dbExecute(pg, "DROP TABLE IF EXISTS cusip_cik_test")

# This code takes only the valid 9-digit CUSIPs from the filings
# that contains then adds on the existing data from all other filings.
cusip_cik_test <-
    cusip_cik %>%
    semi_join(valid_cusip9s, by = c("file_name", "cusip")) %>%
    union_all(
        cusip_cik %>%
            anti_join(valid_cusip9s, by = "file_name")) %>%
    compute(name = "cusip_cik_test", temporary = FALSE)

rs <- dbExecute(pg, "ALTER TABLE cusip_cik_test OWNER TO edgar")
