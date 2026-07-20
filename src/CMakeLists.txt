cmake_minimum_required(VERSION 3.10)
project(download_engine LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 查找 Python
find_package(Python3 COMPONENTS Interpreter Development REQUIRED)

# 下载引擎核心库
add_library(download_engine SHARED
    download_engine.cpp
    http_client.cpp
    python_bridge.cpp
)

target_include_directories(download_engine PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${Python3_INCLUDE_DIRS}
)

target_link_libraries(download_engine
    ${Python3_LIBRARIES}
)

# 平台特定配置
if(ANDROID)
    target_link_libraries(download_engine log)
elseif(UNIX)
    find_package(CURL REQUIRED)
    target_include_directories(download_engine PRIVATE ${CURL_INCLUDE_DIRS})
    target_link_libraries(download_engine ${CURL_LIBRARIES})
endif()
