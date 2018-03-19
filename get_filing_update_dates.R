getLastUpdate <- function(year, quarter) {

    library(rvest)
    library(lubridate)
    # Scrape the html table from the website for the given year and quarter
    filetbl <- read_html(paste("https://www.sec.gov/Archives/edgar/full-index/",
                               year,"/QTR", quarter, "/",sep="")) %>% html_nodes("table") %>% .[[1]] %>% html_table()
    colnames(filetbl)[[3]] <- "Last_Modified"

    # company.gz corresponds to the first row of the html table, so take the first element of filetbl$Last_Modified
    # to return the date of the last update for the year and quarter
    return(mdy_hms(filetbl$Last_Modified[1], tz = "UTC"))


}

makeUpdatesDataframe <- function() {

    library(lubridate)
    library(dplyr)

    date <- today(tz = "UTC")
    numrows <- (year(date) - 1993) * 4 + quarter(date)
    index <- 1:numrows
    years <- 1993 + (index - 1)%/%4L
    quarters <- 1 + (index - 1)%%4L
    updates <- data.frame(year = years, quarter = quarters)
    updates <- updates %>% rowwise() %>% mutate(last_modified = getLastUpdate(year, quarter))
    updates$year <- as.integer(updates$year)
    updates$quarter <- as.integer(updates$quarter)
    return(updates)

}
