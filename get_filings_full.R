# This script update edgar.filings with assigned year range and quarter range

# Add data for years 1993 to 2017 ----
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())
# Set working directory to ../edgar
# setwd(".../edgar")
source("get_filings_function.R")

# Assign year range here
for (year in 1993:2017) {
    for (quarter in 1:4) {
        deleteIndexDataFomDatabase(pg, year, quarter)
        addIndexFileToDatabase(getSECIndexFile(year, quarter))
    }
}
rs <- dbDisconnect(pg)

# Add data for 2018 ----
library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

# Assign year and quarter range here
for (year in 2018) {
    for (quarter in 1) {
        deleteIndexDataFomDatabase(pg, year, quarter)
        addIndexFileToDatabase(getSECIndexFile(year, quarter))
    }
}
rs <- dbDisconnect(pg)