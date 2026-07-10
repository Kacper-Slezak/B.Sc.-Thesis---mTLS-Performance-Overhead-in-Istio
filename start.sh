#!/bin/bash

echo "🚀 Rozpoczynam migrację struktury katalogów na język angielski..."

# 1. Tworzenie nowych katalogów
echo "📁 Tworzenie nowych folderów..."
mkdir -p 01_scripts 02_manifests 03_test_scripts 04_results

# 2. Przenoszenie skryptów
if [ -d "1_skrypty" ]; then
    echo "📦 Przenoszenie zawartości 1_skrypty -> 01_scripts..."
    mv 1_skrypty/* 01_scripts/ 2>/dev/null
    rmdir 1_skrypty 2>/dev/null
fi

# 3. Przenoszenie manifestów YAML
# Uwaga: używam nazwy '2_yaml_mainfest' z literówką, którą miałeś w logach
if [ -d "2_yaml_mainfest" ]; then
    echo "📦 Przenoszenie zawartości 2_yaml_mainfest -> 02_manifests..."
    mv 2_yaml_mainfest/* 02_manifests/ 2>/dev/null
    rmdir 2_yaml_mainfest 2>/dev/null
fi

# 4. Przenoszenie skryptów K6
if [ -d "4_testy_js" ]; then
    echo "📦 Przenoszenie zawartości 4_testy_js -> 03_test_scripts..."
    mv 4_testy_js/* 03_test_scripts/ 2>/dev/null
    rmdir 4_testy_js 2>/dev/null
fi

# 5. Przenoszenie wyników
if [ -d "3_wyniki" ]; then
    echo "📦 Przenoszenie zawartości 3_wyniki -> 04_results..."
    mv 3_wyniki/* 04_results/ 2>/dev/null
    rmdir 3_wyniki 2>/dev/null
fi

echo "✅ Migracja zakończona sukcesem!"
echo ""
echo "Oto Twoja nowa struktura:"
ls -d 01_* 02_* 03_* 04_*
