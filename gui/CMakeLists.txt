cmake_minimum_required(VERSION 3.19)

project(EduHPX VERSION 0.0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Quick QuickControls2)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(eduhpx
    src/main.cpp
)

foreach(example flat_broadcast_16loc_4nodes hierarchical_broadcast_16loc_4nodes mixed_4loc_1node)
    set_source_files_properties(../examples/${example}.csv PROPERTIES QT_RESOURCE_ALIAS examples/${example}.csv)
endforeach()

# Main.qml is served at the root of the module, so that it finds the C++ type RunFile of the module
set_source_files_properties(qml/Main.qml PROPERTIES QT_RESOURCE_ALIAS Main.qml)

qt_add_qml_module(eduhpx
    URI EduHPX
    VERSION 1.0
    QML_FILES
        qml/Main.qml
    SOURCES
        src/run_file.h
        src/run_file.cpp
    RESOURCES
        assets/logo.png
        assets/icon_256.png
        ../examples/flat_broadcast_16loc_4nodes.csv
        ../examples/hierarchical_broadcast_16loc_4nodes.csv
        ../examples/mixed_4loc_1node.csv
)

target_include_directories(eduhpx PRIVATE src)
target_link_libraries(eduhpx PRIVATE Qt6::Core Qt6::Gui Qt6::Quick Qt6::QuickControls2)

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
