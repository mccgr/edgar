#!/usr/bin/env bash
echo "Running get_filings.R ..."
./get_filings.R
echo "Running get_accession_nos.R ..."
./get_accession_nos.R
echo "Running get_filer_ciks.R ..."
./get_filer_ciks.R
echo "Running get_item_nos.R ..."
./get_item_nos.R
echo "Running get_item_no_desc.R ..."
./get_item_no_desc.R
# ./get_server_logs.R
echo "Running get_filing_docs.R ..."
./filing_docs/scrape_filing_docs.R
