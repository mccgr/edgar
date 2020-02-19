import os
import pandas as pd
import numpy as np
from sqlalchemy import create_engine
from schedule_13dg_indexing_functions import get_file_list_df, write_indexes_to_table, conn_string
from multiprocess import Pool
import datetime as dt

function_timeout = 60

engine = create_engine(conn_string)

directory = os.getenv("EDGAR_DIR")

full_df = get_file_list_df(engine)
num_filings = full_df.shape[0]
num_cores = 12
batch_size = 240

num_batches = int(num_filings/batch_size) + 1
num_success = 0

p = Pool(num_cores)
start_time = dt.datetime.now()
for i in range(num_batches):
    
    start = i * batch_size
    
    if(i == num_batches - 1):
        
        end = num_filings  
        
    else:
        
        end = (i + 1) * batch_size 
    
    success = pd.Series(p.map(lambda i: write_indexes_to_table(full_df.loc[i, 'file_name'], full_df.loc[i, 'document'],\
                            full_df.loc[i, 'form_type'], directory, engine, function_timeout) , range(start, end)))
    time_now = dt.datetime.now()
    time_taken = time_now - start_time
    num_success = num_success + success.sum()

    if(i % 50 == 0 or i == num_batches - 1):
        
        print(str(num_success) + ' filings successfully process from ' + str(end))
        print('Time taken: ' + str(time_taken))
        
        
p.close()        
