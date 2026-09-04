cmake_minimum_required(VERSION 3.10.2)

project("aaudio_sink")

# 1. Add Google's Oboe as a subdirectory (assuming 'oboe' folder is placed right here in cpp/)
add_subdirectory(oboe)

# 2. Define your shared library using your existing jni_bridge.cpp file
add_library(
    aaudio_sink
    SHARED
    jni_bridge.cpp
)

# 3. Include Oboe headers so jni_bridge.cpp can see <oboe/Oboe.h>
target_include_directories(
    aaudio_sink
    PRIVATE
    oboe/include
)

find_library(
    log-lib
    log
)

# 4. Link Oboe and Android's log library 
# (Oboe handles aaudio internally, so you don't even need to manually find/link aaudio anymore!)
target_link_libraries(
    aaudio_sink
    oboe
    ${log-lib}
)
