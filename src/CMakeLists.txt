cmake_minimum_required(VERSION 3.10)
project(python_bridge LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 查找 Python
find_package(Python3 COMPONENTS Development REQUIRED)

# 构建共享库
add_library(python_bridge SHARED python_bridge.cpp)

target_include_directories(python_bridge PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${Python3_INCLUDE_DIRS}
)

target_link_libraries(python_bridge
    ${Python3_LIBRARIES}
)

if(ANDROID)
    target_link_libraries(python_bridge log)
endif()
