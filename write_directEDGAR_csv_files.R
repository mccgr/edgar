library(DBI)
library(dplyr, warn.conflicts = FALSE)

pg <- dbConnect(RPostgreSQL::PostgreSQL())

filing_header_info_df <- tbl(pg, sql("SELECT * FROM edgar.filing_heading_info")) %>%
                         rename(CIK = cik, CNAME = cname, RDATE = rdate, CDATE = cdate, YEAR = year, PF = period_focus, FNAME = fname) %>% collect()

filing_header_info_towrite <- filing_header_info_df %>% select(CIK, CNAME, RDATE, CDATE, YEAR, PF, FNAME) %>% distinct() %>% arrange(RDATE)

num_filings <- nrow(filing_header_info_towrite)
batch_size <- 39999

num_batches <- floor(num_filings/batch_size) + 1



for (i in 1:num_batches) {

    start <- (i-1) * batch_size + 1

    if(i == num_batches) {

        end <- num_filings

    } else {

        end <- i * batch_size

    }

    batch <- filing_header_info_towrite[start:end, ]

    write.csv(batch, paste0('/home/shared/directEDGAR/filings_10k_', i, '.csv' ), row.names = FALSE)


}


dbDisconnect(pg)



