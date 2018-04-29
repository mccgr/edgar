For example, for `file_name` value `edgar/data/1527666/0001078782-12-002654.txt`, the documents are listed [here](https://www.sec.gov/Archives/edgar/data/1527666/000107878212002654/0001078782-12-002654-index.htm) and the contents of `filing_docs` is as follows:

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
