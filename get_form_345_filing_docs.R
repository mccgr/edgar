#!/usr/bin/env Rscript
library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL, quietly = TRUE)
library(rvest, quietly = TRUE)
source(get_filing_doc_functions.R)

fil345_regex <- "^[345](/A)?$"

fil345 <- get_filings_by_type(def14_a_regex)

num_filings <- dim(fil345)[1]
batch_size <- 200

num_batches <- ceiling(num_filings/batch_size)
total_time <- 0

for(i in 1:num_batches) {

    start <- i * (batch_size - 1) + 1

    if(i < num_batches) {

        finish <- i * batch_size
        batch <- fil345[start:finish, ]

    } else {

        batch <- fil345[start:num_filings, ]

    }

    time_taken <- system.time(temp <- process_filings(batch))

    if(i %% 1000 == 0) {

        print(paste0("Number of filings processed: ", i * batch_size))
        print("Total time taken: \n")
        print(total_time)

    }

    total_time <- total_time + time_taken

}


