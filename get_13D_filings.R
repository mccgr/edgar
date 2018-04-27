

# Pull together a list of filings to retrieve ----
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

file.list <- dbGetQuery(pg, "
    SET work_mem='1GB';

    SELECT * 
    FROM filings.filings
    WHERE form_type IN ('SC 13G', 'SC 13G/A', 'SC 13D', 'SC 13D/A')
    AND file_name NOT IN (
        SELECT file_name 
        FROM filings.cusip_cik)
")

dbDisconnect(pg)

# Load functions to download filings ----
source("filings/download_filing_functions.R")

# Now, pull text files for each filing ----
file.list$have_file <- NA
to.get <- 1:length(file.list$have_file) #

library(parallel)
# Get the file
system.time({
    file.list$have_file[to.get] <- 
    unlist(mclapply(file.list$file_name[to.get], get_text_file,
                    mc.preschedule=FALSE, mc.cores=6))
})

# Now, pull SGMLs for each filing ----
file.list$sgml_file <- NA
to.get <- 1:length(file.list$sgml_file) #

library(parallel)
# Get the file
system.time({
  file.list$sgml_file[to.get] <- 
    unlist(mclapply(file.list$file_name[to.get], get_sgml_file, 
                  mc.preschedule=FALSE, mc.cores=6))
})


