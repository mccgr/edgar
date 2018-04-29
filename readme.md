# EDGAR

## List of tables

- `filings`: Index of all filings in the SEC EDGAR database (since 1993)
- `accession_numbers`: Each filing has an accession number. This table contains these.
- `cusip_cik`: Table mapping CUSIPs to CIKs. Data are scraped from `SC 13D` and `SC 13G` forms.
- `filer_ciks`: Data on filer CIKs from `SC 13D` and `SC 13G` forms.
- `filing_docs`: Table listing the documents associated with each filing. For example, for `file_name` value `edgar/data/1527666/0001078782-12-002654.txt`, the documents are listed [here](https://www.sec.gov/Archives/edgar/data/1527666/000107878212002654/0001078782-12-002654-index.htm) and the contents of `filing_docs` is as follows:

``` r
library(dplyr, warn.conflicts = FALSE)
library(RPostgreSQL, quietly = TRUE)

pg <- dbConnect(PostgreSQL())

rs <- dbExecute(pg, "SET search_path TO edgar")

filing_docs <- tbl(pg, "filing_docs")

filing_docs %>% 
    filter(file_name=="edgar/data/1527666/0001078782-12-002654.txt")
#> # Source:   lazy query [?? x 6]
#> # Database: postgres 9.6.7 [igow@iangow.me:5432/crsp]
#>     seq description         document      type     size file_name         
#>   <int> <chr>               <chr>         <chr>   <int> <chr>             
#> 1    NA Complete submissio… 0001078782-1… ""     1.61e6 edgar/data/152766…
#> 2    12 JUNE 30, 2012 10-K  f10k063012_1… 10-Q   3.02e5 edgar/data/152766…
#> 3     5 EXHIBIT 32.1 SECTI… f10k063012_e… EX-32… 2.91e3 edgar/data/152766…
#> 4     4 EXHIBIT 31.2 SECTI… f10k063012_e… EX-31… 7.89e3 edgar/data/152766…
#> 5     3 EXHIBIT 31.1 SECTI… f10k063012_e… EX-31… 7.80e3 edgar/data/152766…
#> 6     2 EXHIBIT 23.1 AUDIT… f10k063012_e… EX-23… 3.77e3 edgar/data/152766…
#> 7     1 JUNE 30, 2012 10-K  f10k063012_1… 10-K   3.02e5 edgar/data/152766…

rs <- dbDisconnect(pg)
```
- `item_no`: Table listing item numbers associated with each 8-K filing.
- `item_no_desc`: Table providing explanations for each item number used in 8-K filings. Data extracted from [here](https://www.sec.gov/fast-answers/answersform8khtm.html).

- `server_log`: **Details to come.**

### Tables used in updating tables above
- `server_log_processed`: Table used in updating `server_log`.
- `index_last_modified`: Table used in updating `filings`.
- `filing_docs_processed`: Table used in updating `filing_docs`.

## Code

- [`get_filings.R`](get_filings.R): Script to get index files from EDGAR to populate `filings`.
- [`get_accession_nos.R`](get_accession_nos.R): Script to get the accession numbers from the EDGAR file URLs.
- [`get_filing_docs.R`](get_filing_docs.R): Script to blah 
- [`get_filer_ciks.R`](get_filer_ciks.R): Script to blah
- [`get_item_nos.R`](get_item_nos.R): Script to blah
- [`get_item_no_desc.R`](get_item_no_desc.R): Script to scrape the descriptions for each of the unique item numbers stored in `item_no`, and store them in the table `item_no_desc`.
- [`get_server_logs.R`](server_logs/get_server_logs.R): Script to get server logs from EDGAR to populate `server_log` and `server_log_processed`.
- [`get_13D_filings.R`](get_13D_filings.R): Script to get the 13D filings. Always run this before running `extract_cusips.R`.
- [`get_13D_filing_details`](get_13D_filing_details.R): Extracts the details from the files contained in `edgar.filings`
- [`extract_cusips.pl`](extract_cusips.pl): Contains Perl code which extracts the cusip_cik numbers. This file is used and sourced by extract_cusips.R, so one should run the latter to put the cusip_ciks in the database.
- [`extract_cusips.R`](extract_cusips.R): Puts the cusip_cik numbers in the database.

A script to update the Edgar database is found [here](update_edgar.sh).


