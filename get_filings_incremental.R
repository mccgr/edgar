# This script does incremental update of edgar.filings

library(dplyr)
library(RPostgreSQL)
# Set working directory to ../edgar
# setwd(".../edgar")
source("get_filings_function.R")
pg <- dbConnect(PostgreSQL())

filings <- tbl(pg, sql("SELECT * FROM edgar.filings"))
tmp <- 
    filings %>% 
    summarise(max = max(date_filed)) %>% 
    mutate(tbl_yr = sql("extract(year FROM max)"),
           tbl_qtr = sql("extract(quarter FROM max)")) %>% 
    collect()

tbl_yr <- tmp$tbl_yr
tbl_qtr <- tmp$tbl_qtr
now_yr <- Sys.Date() %>% format("%Y") %>% as.integer()
now_qtr <- ceiling(Sys.Date() %>% format("%m") %>% as.numeric() / 3)

if(tbl_yr < now_yr){
    # Add data for years
    for (year in tbl_yr:(now_yr-1)) {
        for (quarter in 1:4) {
            cat(paste0("Updating year = ", year, ", quarter = ", quarter, "...\n"))
            deleteIndexDataFomDatabase(pg, year, quarter)
            addIndexFileToDatabase(getSECIndexFile(year, quarter))
        }
    }
    tbl_yr <- now_yr
    tbl_qtr <- 1
}
if(tbl_yr == now_yr){
    # Add data for quarters
    year <- now_yr
    if(tbl_qtr > now_qtr){
        cat("No update: table year = current year, table quarter > current quarter.\n")
        cat(paste0("Year = ", now_yr, "\n"))
        cat(paste0("Table quarter = ", tbl_qtr, "\n"))
        cat(paste0("Current quarter = ", now_qtr, "\n"))
    }else{
        for (quarter in tbl_qtr:now_qtr) {
            cat(paste0("Updating year = ", now_yr, ", quarter = ", quarter, "...\n"))
            deleteIndexDataFomDatabase(pg, year, quarter)
            addIndexFileToDatabase(getSECIndexFile(year, quarter))
        }
    }
}else{
    cat("No update: table year > current year.\n")
    cat(paste0("Table year = ", tbl_yr, "\n"))
    cat(paste0("Current year = ", now_yr, "\n"))
}

dbDisconnect(pg)
