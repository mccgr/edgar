extract_value <- function(text, tag) {
  tag <- paste("^<", tag, ">", sep="")
  gsub(tag, "", text[grep(tag, text)])
}

find_text <- function(tag, text) {
  temp <- grep(tag, text)
  if (length(temp)) return(min(temp))
  else (return(0))
}

extract_portion <- function(the_text=NULL, tag) {
 # if (is.null(the_text) | is.null) return(NULL)

  beg.tag <- paste("^<", tag, ">", sep="")
  end.tag <- paste("^</", tag, ">", sep="")

  beg <-  find_text(beg.tag, the_text)
  end <-  find_text(end.tag, the_text)

  if(end>beg) { the_text[beg:end] } else {
    stop()
  }
}

parse13d <- function(text) {
  ## Extract relevant data from a 13D filing.
  ## Also works with 13G filings.
    sub.txt <- extract_portion(text, "SUBJECT-COMPANY")
    sub_cik <- extract_value(sub.txt, "CIK")
    sub_name <- extract_value(sub.txt, "CONFORMED-NAME")

    filer.txt <- try(extract_portion(text, "FILED-BY"))
    if (class(filer.txt) != "try-error") {
      filer_cik <- extract_value(filer.txt, "CIK")
      filer_name <- extract_value(filer.txt, "CONFORMED-NAME")
      return(data.frame(sub_cik, sub_name, filer_cik, filer_name))
    } else {
      return(data.frame(sub_cik=NA, sub_name=NA, filer_cik=NA, filer_name=NA))
    }
}

getSGMLlocation <- function(path) {
  ## Convert a file_name from filings.filings to a path to
  ## the associated SGML file
  sgml_basename <- basename(gsub(".txt$", ".hdr.sgml", path, perl=TRUE))
  sgml_path <- file.path(dirname(path),
                         gsub("(-|\\.hdr\\.sgml$)", "",
                              sgml_basename, perl=TRUE))

  ftp <- file.path("http://www.sec.gov/Archives", sgml_path, sgml_basename)
  return(ftp)
}

extract13Ddata <- function(file_name) {
  text <- try(readLines(getSGMLlocation(file_name)), TRUE)
  if (class(text) == "try-error") return(NA)
  if (length(text)==0) return(NA)
  return(data.frame(file_name, parse13d(text)))
}

library(RPostgreSQL)
pg <- dbConnect(PostgreSQL())

filings <- dbGetQuery(pg, "

  SET work_mem='1GB';

  SELECT *
  FROM filings.filings
  WHERE form_type IN ('SC 13D', 'SC 13D/A')
    AND file_name NOT IN (
      SELECT file_name
      FROM filings.filing_details_13d)")
dim(filings)
dbDisconnect(pg)
removeErrors <- function(a_list) {
  a_list[unlist(lapply(a_list, function(x) { class(x)!="try-error"}))]
}

library(parallel)
batch_rows <- 100
for (i in 0:floor((dim(filings)[1])/batch_rows)) {
    filing_list <- NULL
    from <- i*batch_rows+1
    to <- min((i+1)*batch_rows, dim(filings)[1])

    if (to >= from) {
      range <- from:to
    } else {
      range <- NULL
    }

    filing_list <- mclapply(filings$file_name[range], extract13Ddata,
                            mc.cores=6)

    if (!is.null(filing_list) & !is.null(range)) {
      filing_list <- removeErrors(filing_list)
      filing_details <- do.call(rbind, filing_list)
      rs <- dbWriteTable(pg, c("filings","filing_details_13d"), filing_details,
                 append=TRUE, row.names=FALSE)
      rs <- dbGetQuery(pg, "VACUUM filings.filing_details_13d")
    }
}

rs <- dbGetQuery(pg, "
    DELETE FROM filings.filing_details_13d
    WHERE file_name IS NULL;")
