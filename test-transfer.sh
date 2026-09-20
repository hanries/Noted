#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p build/ModuleCache work/TransferQA
swiftc -module-cache-path build/ModuleCache Noted/Notebook.swift Noted/NotebookTransfer.swift Tests/Transfer/main.swift -o build/noted-transfer-tests
build/noted-transfer-tests "$PWD/work/TransferQA"
