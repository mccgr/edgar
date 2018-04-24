# EDGAR

## List of tables

- `filings`: Table of the filings in the edgar database, starting from the first quarter of 1993
- `index_last_modified`: table of 

- `accession_numbers`: blah blah
- `cusip_cik`: blah blah
- `filer_ciks`: blah blah
- `filing_docs`: blah blah
- `filing_docs_processed`: blah blah

- `item_no`: blah blah
- `item_no_desc`: blah blah
- `server_log`: blah blah
- `server_log_processed`: blah blah

## Code

- [`get_filings.R`](https://github.com/iangow-public/edgar/blob/master/get_filings.R): Script to get index files from EDGAR to populate `filings`.
- [`get_accession_nos.R`](https://github.com/iangow-public/edgar/blob/master/get_accession_nos.R): Script to get the accession numbers from the EDGAR file urls
- [`get_filing_docs.R`](https://github.com/iangow-public/edgar/blob/master/get_filing_docs.R): Script to blah 
- [`get_filer_ciks.R`](https://github.com/iangow-public/edgar/blob/master/get_filer_ciks.R): Script to blah
- [`get_item_nos.R`](https://github.com/iangow-public/edgar/blob/master/get_item_nos.R): Script to blah
- [`get_item_no_desc.R`](https://github.com/iangow-public/edgar/blob/master/get_item_no_desc.R): Script to scrape the descriptions for each of the unique item numbers stored in `item_no`, and store them in the table `item_no_desc`.
- [`get_server_logs.R`](https://github.com/iangow-public/edgar/blob/master/server_logs/get_server_logs.R): Script to get server logs from EDGAR to populate `server_log` and `server_log_processed`

## Bash script to update the Edgar database

```
chmod a+x get_filings.R
chmod a+x get_accession_nos.R
chmod a+x get_filing_docs.R 
chmod a+x get_filer_ciks.R 
chmod a+x get_item_nos.R 
chmod a+x get_item_no_desc.R 
chmod a+x get_server_logs.R 

./get_filings.R
./get_accession_nos.R
./get_filing_docs.R 
./get_filer_ciks.R 
./get_item_nos.R 
./get_item_no_desc.R 
./get_server_logs.R 

```
