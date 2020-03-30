library(DBI)
library(dplyr, warn.conflicts = FALSE)
library(lubridate)
library(parallel)


getSGMLlocation <- function(path) {
    ## Convert a file_name from edgar.filings to a path to
    ## the associated SGML file
    sgml_basename <- basename(gsub(".txt$", ".hdr.sgml", path, perl=TRUE))
    sgml_path <- file.path(dirname(path),
                           gsub("(-|\\.hdr\\.sgml$)", "",
                                sgml_basename, perl=TRUE))

    ftp <- file.path("https://www.sec.gov/Archives", sgml_path, sgml_basename)
    return(ftp)
}


get_cname <- function(lines, cik) {

    filer_start_line_index <- which(grepl('^<FILER>', lines))
    filer_end_line_index <- which(grepl('^</FILER>', lines))


    cik_line_index <- which(grepl(paste0('^<CIK>', stringr::str_pad(cik, width=10, pad="0"), '$'), lines))[1]

    filer_end_line_index <- filer_end_line_index[which(filer_end_line_index > cik_line_index)[1]]
    num_starts_before_cik <- sum(filer_start_line_index < cik_line_index)
    filer_start_line_index <- filer_start_line_index[which(filer_start_line_index < cik_line_index)[num_starts_before_cik]]


    filer_lines <- lines[filer_start_line_index:filer_end_line_index]

    conformed_name_line <- filer_lines[grepl('^<CONFORMED-NAME>', filer_lines)]

    cname <- gsub('^<CONFORMED-NAME>', '', conformed_name_line)

    return(cname)

}





get_rdate <- function(lines) {

    header_line <- lines[grepl('^<(SEC|IMS)-HEADER>', lines)]
    return(paste0('R', stringr::str_match(header_line, '[0-9]{8}$')[1]))

}

get_cdate <- function(lines) {

    period_line_tf <- grepl('^<PERIOD>', lines)
    filing_date_line_tf <- grepl('^<FILING_DATE>', lines)

    if(sum(period_line_tf) > 0) {

        period_line <- lines[period_line_tf]
        return(paste0('C', stringr::str_match(period_line, '[0-9]{8}$')[1]))

    } else if(sum(filing_date_line_tf) > 0) {

        filing_date_line <- lines[filing_date_line_tf]
        return(paste0('C', stringr::str_match(filing_date_line, '[0-9]{8}$')[1]))

    } else {

        header_line <- lines[grepl('^<(SEC|IMS)-HEADER>', lines)]
        return(paste0('C', stringr::str_match(header_line, '[0-9]{8}$')[1]))

    }


}

get_fname <- function(file_name) {

    accession_no <- stringr::str_match(file_name, '[0-9]{10}-[0-9]{2}-[0-9]{6}.txt$')[1]
    accession_no <- gsub('.txt$', '', accession_no)
    accession_no <- gsub('-', '', accession_no)

    last_two_digits <- stringr::str_match(accession_no, '[0-9]{2}$')[1]

    return(paste0('F', last_two_digits))

}

get_header_df <- function(file_name, form_type, cik) {

    sgml_address <- getSGMLlocation(file_name)
    lines <- readLines(sgml_address)

    cname <- get_cname(lines, cik)
    rdate <- get_rdate(lines)
    year <- year(ymd(gsub('^R', '', rdate)))
    cdate <- get_cdate(lines)
    fname <- get_fname(file_name)
    period_focus <- 'FY'

    df <- data.frame(file_name = file_name, form_type = form_type, cik = cik, cname = cname, rdate = rdate, cdate = cdate, year = year, period_focus = period_focus, fname = fname)

    return(df)

}



write_header <- function(file_name, form_type, cik) {

    pg <- dbConnect(RPostgreSQL::PostgreSQL())

    try({
    new_table <- !dbExistsTable(pg, c("edgar", "filing_heading_info"))

    df <- get_header_df(file_name, form_type, cik)

    rs <- dbWriteTable(pg, c("edgar", "filing_heading_info"), df, append = !new_table, row.names = FALSE)

    success <- TRUE

    }, {success <- FALSE})

    dbDisconnect(pg)

    return(success)

}


get_filings <- function(form_type_regex) {

    pg <- dbConnect(RPostgreSQL::PostgreSQL())

    new_table <- !dbExistsTable(pg, c("edgar", "filing_heading_info"))

    if(new_table) {

        filings_sql <- paste0("SELECT file_name, form_type, cik FROM edgar.filings WHERE form_type ~ '", form_type_regex, "'")

    } else {


        filings_sql <- paste0("SELECT a.file_name, a.form_type, a.cik FROM edgar.filings AS a
                        LEFT JOIN edgar.filing_heading_info AS b
                        USING(file_name)
                        WHERE a.form_type ~ '", form_type_regex, "'
                        AND b.file_name IS NULL
                       ")
    }

    df <- tbl(pg, sql(filings_sql)) %>% collect()


    dbDisconnect(pg)

    return(df)

}



pg <- dbConnect(RPostgreSQL::PostgreSQL())


tenk_df <- get_filings("^10-K(/A)?$")

num_filings <- nrow(tenk_df)
batch_size <- 200
num_cores <- 12
num_batches <- floor(num_filings/batch_size) + 1
total_time <- 0
num_success <- 0




for (i in 1:num_batches) {

    start <- (i-1) * batch_size + 1

    if(i == num_batches) {

        end <- num_filings

    } else {

        end <- i * batch_size

    }

    batch <- tenk_df[start:end, ]

    total_time <- total_time + system.time(success_vec <- unlist(mclapply(1:nrow(batch),
                                                            function(i) {write_header(batch$file_name[i], batch$form_type[i], batch$cik[i])}, mc.cores = num_cores)))

    num_success <- num_success + sum(success_vec)



    print(paste0(num_success, ' processed out of ', end, ' ciks'))
    print(paste0('Time taken: ', total_time))


}


dbDisconnect(pg)





