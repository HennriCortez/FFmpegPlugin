cmake_minimum_required(VERSION 3.10.2)

project("aaudio_sink")

# Define your shared library and link Android's native aaudio and log libraries
add_library(
    aaudio_sink
    SHARED
    jni_bridge.cpp
)

find_library(
    log-lib
    log
)

find_library(
    aaudio-lib
    aaudio
)

target_link_libraries(
    aaudio_sink
    ${log-lib}
    ${aaudio-lib}
)
