cmake_minimum_required(VERSION 3.19)

project(EduHPX VERSION 0.0.3 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Quick QuickControls2)
# the 3D view of the tree (qml/Tree3D.qml) needs Qt Quick 3D; without it the program is built and shows a note in that view
find_package(Qt6 6.5 QUIET OPTIONAL_COMPONENTS Quick3D)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(eduhpx
    src/main.cpp
)

# all example run files are built into the program (File > Examples), with examples/index.json as their list
file(GLOB EXAMPLE_FILES ${CMAKE_CURRENT_SOURCE_DIR}/../examples/*.csv ${CMAKE_CURRENT_SOURCE_DIR}/../examples/index.json)
foreach(example ${EXAMPLE_FILES})
    get_filename_component(example_name ${example} NAME)
    set_source_files_properties(${example} PROPERTIES QT_RESOURCE_ALIAS examples/${example_name})
endforeach()

# Main.qml is served at the root of the module, so that it finds the C++ type RunFile of the module
set_source_files_properties(qml/Main.qml PROPERTIES QT_RESOURCE_ALIAS Main.qml)
set_source_files_properties(qml/ExampleList.qml PROPERTIES QT_RESOURCE_ALIAS ExampleList.qml)
set_source_files_properties(qml/Tree3D.qml PROPERTIES QT_RESOURCE_ALIAS Tree3D.qml)

qt_add_qml_module(eduhpx
    URI EduHPX
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/ExampleList.qml
        qml/Tree3D.qml
    SOURCES
        src/run_file.h
        src/run_file.cpp
    RESOURCES
        assets/logo.png
        assets/icon_256.png
        ${EXAMPLE_FILES}
)

target_include_directories(eduhpx PRIVATE src)
target_link_libraries(eduhpx PRIVATE Qt6::Core Qt6::Gui Qt6::Quick Qt6::QuickControls2)
if(TARGET Qt6::Quick3D)
    target_link_libraries(eduhpx PRIVATE Qt6::Quick3D)    # makes the deploy tools bundle it
endif()

set_source_files_properties(assets/EduHPX.icns PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
target_sources(eduhpx PRIVATE assets/EduHPX.icns)

set_target_properties(eduhpx PROPERTIES
    MACOSX_BUNDLE_ICON_FILE EduHPX.icns
    MACOSX_BUNDLE_GUI_IDENTIFIER org.eduhpx.eduhpx
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

include(GNUInstallDirs)
install(TARGETS eduhpx BUNDLE DESTINATION . RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
# the example run files are built into the app (File > Examples); they are also installed as plain files
install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/../examples/ DESTINATION ${CMAKE_INSTALL_DATADIR}/eduhpx/examples FILES_MATCHING PATTERN "*.csv" PATTERN "README.md")
