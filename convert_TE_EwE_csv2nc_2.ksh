#!/bin/bash

IN_PATH=./csv

# source mapping functions
. ./mappings

# create folders
mkdir -p ncdf

# loop over csv files in $IN_PATH
for FILE in $IN_PATH/*.csv;do

    # skip converting csv files that were already converted to unicode-8
    [[ $(echo $FILE|grep utf) ]] && continue

    echo "processing $FILE ..."

    # convert to utf-8 file encoding
    IFILE=$IN_PATH/$(basename $FILE .csv).utf.csv
    iconv -t utf-8 $FILE > $IFILE

    # extract parameters from csv file name
    MODEL=$(basename $IFILE .utf.csv|awk -F"_" '{print $2}')
    GCM=$(basename $IFILE .utf.csv|awk -F"_" '{print $3}')
    REGION=$(basename $IFILE .utf.csv|awk -F"_" '{print $1}')
    VAR=$(basename $IFILE .utf.csv|awk -F"_" '{print $7}')
    SCEN=$(basename $IFILE .utf.csv|awk -F"_" '{print $4}')

    # get first and last year from data rows
    STARTYEAR=$(awk -F"," 'NR==2 {print $1}' $IFILE|cut -c -4)
    ENDYEAR=$(awk -F"," 'END {print $1}' $IFILE|cut -c -4)

    # set output file name, data counter and time steps array
    OFILE=ncdf/${MODEL}_${GCM}_${SCEN}_${VAR}_${REGION}_monthly_${STARTYEAR}_${ENDYEAR}.nc
    DATA_COUNT=$(tail -n +2 $IFILE | wc -l)
    TIME=$(seq -s, 0 $DATA_COUNT)

    # map variable and model
    map_VAR $VAR
    map_MODEL $MODEL

    # read data from csv file
    DATA=$(awk -F"," 'NR>1 {print $NF}' $IFILE| tr '\n' ','| sed '$s/,$/\n/') #> temp_monthly_ncdf.cdl

    # build cdl file
    cat <<EOF >temp_monthly_ncdf.cdl
netcdf monthly_output_cdf {
dimensions:
        lon = 1 ;
        lat = 1 ;
        time = UNLIMITED ;
variables:
        float lon(lon) ;
                lon:long_name = "longitude" ;
                lon:units = "degrees_east" ;
                lon:standard_name = "longitude" ;
        float lat(lat) ;
                lat:long_name = "latitude" ;
                lat:units = "degrees_north" ;
                lat:standard_name = "latitude" ;
        float time(time) ;
                time:units = "months since ${STARTYEAR}-01-01" ;
                time:calendar = "standard" ;
        float ${VAR}(time, lat, lon) ;
                ${VAR}:standard_name = "$STD_NAME" ;
                ${VAR}:long_name = "$LONG_NAME" ;
                ${VAR}:units = "$UNIT" ;
                ${VAR}:_FillValue = 1.e+20f ;

// global attributes:
                :title = "Impact model output for ISI-MIP2" ;
                :comment1 = "$COMMENT1" ;
                :comment2 = "$COMMENT2" ;
                :institution = "$INSTITUTE" ;
                :contact = "$CONTACT" ;

data:

 lon = 0.0 ;
 lat = 0.0 ;

 time = $TIME;
 $VAR = $DATA;

}

EOF

    # create NetCDF file from cdl file
    ncgen -o $OFILE temp_monthly_ncdf.cdl && rm temp_monthly_ncdf.cdl

    # set reference time
    cdo -s -setreftime,1860-01-01,00:00:00,1months $OFILE $OFILE.tmp && mv $OFILE.tmp $OFILE

    # convert to compressed NetCDF4
    nccopy -k4 -d5 $OFILE ${OFILE}4 && rm $OFILE

done
