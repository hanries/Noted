#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p build/ModuleCache
swiftc -module-cache-path build/ModuleCache Noted/Notebook.swift Tests/main.swift -o build/noted-tests
build/noted-tests
