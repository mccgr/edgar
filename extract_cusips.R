#!/usr/bin/env Rscript

# Get a list of files that need to be processed ----
library(dplyr, warn.conflicts = FALSE)
library(DBI)
pg <- dbConnect(RPostgreSQL::PostgreSQL())

if (!dbExistsTable(pg, c("edgar", "cusip_cik"))) {
    dbGetQuery(pg, "
        CREATE TABLE edgar.cusip_cik
            (
              file_name text,
              cusip text,
              cik integer,
              company_name text,
              format text
            )

        GRANT SELECT ON TABLE edgar.cusip_cik TO crsp_basic;

        CREATE INDEX ON edgar.cusip_cik (cusip);
        CREATE INDEX ON edgar.cusip_cik (cik);")
}

# Note that this assumes that streetevents.calls is up to date.
dbGetQuery(pg, "SET work_mem='2GB'")
filings <- tbl(pg, sql("SELECT * FROM edgar.filings"))
cusip_cik <- tbl(pg, sql("SELECT * FROM edgar.cusip_cik"))
file_list <-
    filings %>%
    filter(form_type %in% c('SC 13G', 'SC 13G/A', 'SC 13D', 'SC 13D/A')) %>%
    anti_join(cusip_cik, by="file_name") %>%
    collect()

rs <- dbDisconnect(pg)

# Create function to parse a SC 13D or SC 13F filing ----
parseFile <- function(file_name) {

    # Parse the indicated file using a Perl script
    system(paste("perl extract_cusips.pl", file_name),
           intern = TRUE)
}

# Apply parsing function to files ----
library(parallel)
system.time({
    res <- unlist(mclapply(file_list$file_name, parseFile, mc.cores=12))
})
