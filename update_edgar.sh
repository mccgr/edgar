#!/usr/bin/env bash
echo "Running get_filings.R ..."
$EDGAR_CODE_DIR/./get_filings.R
echo "Running get_accession_nos.R ..."
$EDGAR_CODE_DIR/./get_accession_nos.R
echo "Running get_filer_ciks.R ..."
$EDGAR_CODE_DIR/./get_filer_ciks.R
echo "Running get_item_nos.R ..."
$EDGAR_CODE_DIR/./item_nos/get_item_nos.R
echo "Running get_item_no_desc.R ..."
$EDGAR_CODE_DIR/./item_nos/get_item_no_desc.R
# $EDGAR_CODE_DIR/./get_server_logs.R
echo "Running scrape_filing_docs.R ..."
$EDGAR_CODE_DIR/./filing_docs/scrape_filing_docs.R
