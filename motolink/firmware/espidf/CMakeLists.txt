cmake_minimum_required(VERSION 3.16)
set(IDF_TARGET esp32s3)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(motolink VERSION 0.1.0)

# Custom partition table
set(PARTITION_TABLE_CSV partitions.csv)
set(PARTITION_TABLE_OFFSET 0x8000)

